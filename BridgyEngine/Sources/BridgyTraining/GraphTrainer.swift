import BridgyEngine
import Foundation
import Metal
import MetalPerformanceShadersGraph

/// A batch of positions to learn from, already encoded.
public struct TrainingBatch: Sendable {
    public var count: Int
    /// `count × side × side × planes`.
    public var inputs: [Float]
    /// `count × side²`: the search's move distribution, on the lattice.
    public var policy: [Float]
    /// `count × side²`: one where a legal move is, zero elsewhere.
    public var legal: [Float]
    /// `count`: +1 if the player to move went on to win, −1 if not.
    public var outcome: [Float]
}

/// Trains a network on the GPU with MPSGraph.
///
/// The graph is built once for one board size and batch size: the same network
/// `NeuralNetwork` runs on the CPU, a loss (policy cross-entropy, value squared
/// error, weight decay), its gradients, and an Adam step that writes the new
/// weights back into graph variables. A training step is then a single
/// `run`, with the weights never leaving the GPU until they are asked for.
public final class GraphTrainer {
    public let architecture: NetworkArchitecture
    public let side: Int
    public let batchSize: Int

    private let graph = MPSGraph()
    private let device: MPSGraphDevice
    private let queue: MTLCommandQueue

    private let variables: [MPSGraphTensor]
    private let inputs: MPSGraphTensor
    private let policyTarget: MPSGraphTensor
    private let legalMask: MPSGraphTensor
    private let valueTarget: MPSGraphTensor
    private let stepSize: MPSGraphTensor
    private let policyLoss: MPSGraphTensor
    private let valueLoss: MPSGraphTensor
    private let updates: [MPSGraphOperation]

    private let probe: MPSGraphTensor
    private let probeLogits: MPSGraphTensor
    private let probeValue: MPSGraphTensor

    private let beta1: Float = 0.9
    private let beta2: Float = 0.999
    private var step = 0

    public enum Failure: LocalizedError {
        case noGPU
        case simulator
        public var errorDescription: String? {
            switch self {
            case .noGPU: "This device has no GPU that Metal can train on."
            case .simulator: "Training needs a real GPU, and the Simulator doesn't offer one to MPSGraph. Train on a device or on a Mac; agents trained there play here."
            }
        }
    }

    /// Whether this device can train at all. The Simulator cannot: MPSGraph
    /// raises an Objective-C exception creating its device there, which Swift
    /// cannot catch, so it has to be ruled out before trying.
    public static var unavailableReason: Failure? {
        #if targetEnvironment(simulator)
        return .simulator
        #else
        return MTLCreateSystemDefaultDevice() == nil ? .noGPU : nil
        #endif
    }

    public init(weights: NetworkWeights, boardSize: Int, batchSize: Int, weightDecay: Float) throws {
        if let reason = Self.unavailableReason { throw reason }
        guard let metal = MTLCreateSystemDefaultDevice(), let queue = metal.makeCommandQueue() else {
            throw Failure.noGPU
        }
        self.device = MPSGraphDevice(mtlDevice: metal)
        self.queue = queue
        self.architecture = weights.architecture
        self.side = 2 * boardSize + 1
        self.batchSize = batchSize

        let graph = self.graph
        let tensors = weights.architecture.tensors
        let variables = zip(tensors, weights.values).map { tensor, values in
            graph.variable(
                with: values.withUnsafeBufferPointer { Data(buffer: $0) },
                shape: tensor.shape.map { NSNumber(value: $0) },
                dataType: .float32,
                name: tensor.name
            )
        }
        self.variables = variables

        let points = side * side
        let planes = BoardEncoding.planes
        func placeholder(_ shape: [Int], _ name: String) -> MPSGraphTensor {
            graph.placeholder(shape: shape.map { NSNumber(value: $0) }, dataType: .float32, name: name)
        }
        inputs = placeholder([batchSize, side, side, planes], "inputs")
        policyTarget = placeholder([batchSize, points], "policyTarget")
        legalMask = placeholder([batchSize, points], "legal")
        valueTarget = placeholder([batchSize, 1], "valueTarget")
        stepSize = placeholder([1], "stepSize")
        probe = placeholder([1, side, side, planes], "probe")

        let arch = weights.architecture
        let (logits, value) = Self.forward(inputs, graph: graph, variables: variables, arch: arch, side: side)
        (probeLogits, probeValue) = Self.forward(probe, graph: graph, variables: variables, arch: arch, side: side)

        // Policy: cross-entropy against the search's visit distribution, over
        // legal moves only. Everything else is pushed to a huge negative logit,
        // where softmax gives it nothing and the target is zero anyway.
        let one = graph.constant(1, dataType: .float32)
        let offBoard = graph.multiplication(
            graph.subtraction(legalMask, one, name: nil),
            graph.constant(1e4, dataType: .float32),
            name: nil
        )
        let masked = graph.addition(logits, offBoard, name: nil)
        let probabilities = graph.softMax(with: masked, axis: 1, name: nil)
        let logProbabilities = graph.logarithm(
            with: graph.addition(probabilities, graph.constant(1e-9, dataType: .float32), name: nil),
            name: nil
        )
        let perPosition = graph.reductionSum(
            with: graph.multiplication(policyTarget, logProbabilities, name: nil),
            axes: [1],
            name: nil
        )
        let policyLoss = graph.negative(with: graph.mean(of: perPosition, axes: [0, 1], name: nil), name: nil)

        // Value: squared error against how the game actually went.
        let valueLoss = graph.mean(
            of: graph.square(with: graph.subtraction(value, valueTarget, name: nil), name: nil),
            axes: [0, 1],
            name: nil
        )

        // Weight decay on weights, not biases.
        var decay = graph.constant(0, dataType: .float32)
        for (tensor, variable) in zip(tensors, variables) where !tensor.isBias {
            let squares = graph.reductionSum(
                with: graph.square(with: variable, name: nil),
                axes: (0..<tensor.shape.count).map { NSNumber(value: $0) },
                name: nil
            )
            decay = graph.addition(decay, graph.reshape(squares, shape: [1], name: nil), name: nil)
        }
        let total = graph.addition(
            graph.addition(graph.reshape(policyLoss, shape: [1], name: nil),
                           graph.reshape(valueLoss, shape: [1], name: nil), name: nil),
            graph.multiplication(decay, graph.constant(Double(weightDecay), dataType: .float32), name: nil),
            name: nil
        )
        self.policyLoss = policyLoss
        self.valueLoss = valueLoss

        // Adam. The bias correction is folded into the step size, which is fed
        // in each step, so the graph itself never needs a step counter.
        let gradients = graph.gradients(of: total, with: variables, name: nil)
        let b1 = graph.constant(Double(beta1), dataType: .float32)
        let b2 = graph.constant(Double(beta2), dataType: .float32)
        let oneMinusB1 = graph.constant(Double(1 - beta1), dataType: .float32)
        let oneMinusB2 = graph.constant(Double(1 - beta2), dataType: .float32)
        let epsilon = graph.constant(1e-8, dataType: .float32)
        var updates: [MPSGraphOperation] = []
        for (tensor, variable) in zip(tensors, variables) {
            guard let gradient = gradients[variable] else { continue }
            let zeros = Data(count: tensor.count * 4)
            let shape = tensor.shape.map { NSNumber(value: $0) }
            let m = graph.variable(with: zeros, shape: shape, dataType: .float32, name: nil)
            let v = graph.variable(with: zeros, shape: shape, dataType: .float32, name: nil)
            let newM = graph.addition(graph.multiplication(b1, m, name: nil),
                                      graph.multiplication(oneMinusB1, gradient, name: nil), name: nil)
            let newV = graph.addition(graph.multiplication(b2, v, name: nil),
                                      graph.multiplication(oneMinusB2, graph.square(with: gradient, name: nil), name: nil),
                                      name: nil)
            let change = graph.division(
                graph.multiplication(stepSize, newM, name: nil),
                graph.addition(graph.squareRoot(with: newV, name: nil), epsilon, name: nil),
                name: nil
            )
            updates.append(graph.assign(m, tensor: newM, name: nil))
            updates.append(graph.assign(v, tensor: newV, name: nil))
            updates.append(graph.assign(variable, tensor: graph.subtraction(variable, change, name: nil), name: nil))
        }
        self.updates = updates
    }

    /// The network, as `NeuralNetwork` computes it on the CPU.
    private static func forward(
        _ x: MPSGraphTensor,
        graph: MPSGraph,
        variables: [MPSGraphTensor],
        arch: NetworkArchitecture,
        side: Int
    ) -> (logits: MPSGraphTensor, value: MPSGraphTensor) {
        let descriptor = MPSGraphConvolution2DOpDescriptor(
            strideInX: 1, strideInY: 1,
            dilationRateInX: 1, dilationRateInY: 1,
            groups: 1,
            paddingStyle: .TF_SAME,
            dataLayout: .NHWC,
            weightsLayout: .HWIO
        )!
        func conv(_ input: MPSGraphTensor, _ index: Int) -> MPSGraphTensor {
            graph.addition(
                graph.convolution2D(input, weights: variables[index], descriptor: descriptor, name: nil),
                variables[index + 1],
                name: nil
            )
        }
        func dense(_ input: MPSGraphTensor, _ index: Int) -> MPSGraphTensor {
            graph.addition(
                graph.matrixMultiplication(primary: input, secondary: variables[index], name: nil),
                variables[index + 1],
                name: nil
            )
        }

        let batch = x.shape![0]
        var h = graph.reLU(with: conv(x, 0), name: nil)
        for block in 0..<arch.blocks {
            let first = 2 + block * 4
            let a = graph.reLU(with: conv(h, first), name: nil)
            let b = conv(a, first + 2)
            h = graph.reLU(with: graph.addition(h, b, name: nil), name: nil)
        }
        let heads = 2 + arch.blocks * 4
        let logits = graph.reshape(conv(h, heads), shape: [batch, NSNumber(value: side * side)], name: nil)

        let reduced = graph.reLU(with: conv(h, heads + 2), name: nil)
        let pooled = graph.reshape(
            graph.mean(of: reduced, axes: [1, 2], name: nil),
            shape: [batch, NSNumber(value: arch.valueChannels)],
            name: nil
        )
        let hidden = graph.reLU(with: dense(pooled, heads + 4), name: nil)
        let value = graph.tanh(with: dense(hidden, heads + 6), name: nil)
        return (logits, value)
    }

    // MARK: - Running

    private func data(_ values: [Float], _ shape: [Int]) -> MPSGraphTensorData {
        MPSGraphTensorData(
            device: device,
            data: values.withUnsafeBufferPointer { Data(buffer: $0) },
            shape: shape.map { NSNumber(value: $0) },
            dataType: .float32
        )
    }

    private func floats(_ data: MPSGraphTensorData) -> [Float] {
        let count = data.shape.reduce(1) { $0 * $1.intValue }
        var result = [Float](repeating: 0, count: count)
        result.withUnsafeMutableBytes { data.mpsndarray().readBytes($0.baseAddress!, strideBytes: nil) }
        return result
    }

    /// One Adam step on `batch`, returning the policy and value losses before it.
    @discardableResult
    public func train(_ batch: TrainingBatch, learningRate: Float) -> (policy: Float, value: Float) {
        precondition(batch.count == batchSize, "The graph was built for batches of \(batchSize)")
        step += 1
        let t = Float(step)
        let corrected = learningRate * (1 - powf(beta2, t)).squareRoot() / (1 - powf(beta1, t))
        let points = side * side
        let results = graph.run(
            with: queue,
            feeds: [
                inputs: data(batch.inputs, [batchSize, side, side, BoardEncoding.planes]),
                policyTarget: data(batch.policy, [batchSize, points]),
                legalMask: data(batch.legal, [batchSize, points]),
                valueTarget: data(batch.outcome, [batchSize, 1]),
                stepSize: data([corrected], [1])
            ],
            targetTensors: [policyLoss, valueLoss],
            targetOperations: updates
        )
        return (floats(results[policyLoss]!)[0], floats(results[valueLoss]!)[0])
    }

    /// The network's output for one encoded position, computed on the GPU. Only
    /// used to check the CPU path gives the same answer.
    public func evaluate(_ input: [Float]) -> NeuralNetwork.Output {
        let results = graph.run(
            with: queue,
            feeds: [probe: data(input, [1, side, side, BoardEncoding.planes])],
            targetTensors: [probeLogits, probeValue],
            targetOperations: nil
        )
        return NeuralNetwork.Output(logits: floats(results[probeLogits]!), value: floats(results[probeValue]!)[0])
    }

    /// The current weights, copied back from the GPU.
    public func weights() -> NetworkWeights {
        let results = graph.run(with: queue, feeds: [:], targetTensors: variables, targetOperations: nil)
        return NetworkWeights(architecture: architecture, values: variables.map { floats(results[$0]!) })
    }
}
