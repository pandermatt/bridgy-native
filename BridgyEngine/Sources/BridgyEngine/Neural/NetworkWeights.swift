import Foundation

/// The shape of a network: how wide, how deep, how big its value head.
///
/// The network is fully convolutional over the board's lattice, so nothing here
/// depends on board size. One trained at 5×5 will play 9×9 — not as well as one
/// trained there, but legally and sensibly.
public struct NetworkArchitecture: Sendable, Hashable, Codable {
    /// Feature channels carried through the residual tower.
    public var channels: Int
    /// Residual blocks, each two 3×3 convolutions. Each block lets information
    /// travel two lattice steps further, which is one cell.
    public var blocks: Int
    /// Channels the value head reduces to before pooling.
    public var valueChannels: Int
    /// Width of the value head's hidden layer.
    public var valueHidden: Int

    public init(channels: Int = 32, blocks: Int = 4, valueChannels: Int = 8, valueHidden: Int = 32) {
        self.channels = channels
        self.blocks = blocks
        self.valueChannels = valueChannels
        self.valueHidden = valueHidden
    }

    /// One tensor of the network: its name and shape.
    ///
    /// Convolution weights are laid out height, width, input, output (HWIO) —
    /// what both the CPU path's im2col and MPSGraph's `.HWIO` expect — and dense
    /// weights input by output.
    public struct Tensor: Sendable, Hashable {
        public let name: String
        public let shape: [Int]
        public var count: Int { shape.reduce(1, *) }
        /// Inputs feeding each output, for initialisation.
        public let fanIn: Int
        public let isBias: Bool
    }

    /// Every parameter in the order they are stored, trained and loaded.
    public var tensors: [Tensor] {
        let c = channels
        let planes = BoardEncoding.planes
        func conv(_ name: String, _ k: Int, _ i: Int, _ o: Int) -> [Tensor] {
            [Tensor(name: name + ".w", shape: [k, k, i, o], fanIn: k * k * i, isBias: false),
             Tensor(name: name + ".b", shape: [o], fanIn: k * k * i, isBias: true)]
        }
        func dense(_ name: String, _ i: Int, _ o: Int) -> [Tensor] {
            [Tensor(name: name + ".w", shape: [i, o], fanIn: i, isBias: false),
             Tensor(name: name + ".b", shape: [o], fanIn: i, isBias: true)]
        }
        var result = conv("stem", 3, planes, c)
        for block in 0..<blocks {
            result += conv("block\(block).a", 3, c, c)
            result += conv("block\(block).b", 3, c, c)
        }
        result += conv("policy", 1, c, 1)
        result += conv("value", 1, c, valueChannels)
        result += dense("value.fc1", valueChannels, valueHidden)
        result += dense("value.fc2", valueHidden, 1)
        return result
    }

    public var parameterCount: Int { tensors.reduce(0) { $0 + $1.count } }
}

/// A network's parameters, as plain arrays of floats.
///
/// A value type so an engine holding it stays `Sendable` and can be copied into
/// every tournament game for free (the arrays are copy-on-write).
public struct NetworkWeights: Sendable, Hashable {
    public let architecture: NetworkArchitecture
    /// One array per entry of `architecture.tensors`, in the same order.
    public private(set) var values: [[Float]]

    public init(architecture: NetworkArchitecture, values: [[Float]]) {
        precondition(values.count == architecture.tensors.count, "Wrong number of tensors")
        for (tensor, array) in zip(architecture.tensors, values) {
            precondition(array.count == tensor.count, "Tensor \(tensor.name) has the wrong size")
        }
        self.architecture = architecture
        self.values = values
    }

    /// He initialisation, scaled down on the last layer of each residual block
    /// so a fresh tower starts close to the identity and trains without a
    /// normalisation layer.
    public init(random architecture: NetworkArchitecture, seed: UInt64) {
        var rng = SeededRandomNumberGenerator(seed: seed)
        self.architecture = architecture
        self.values = architecture.tensors.map { tensor in
            guard !tensor.isBias else { return [Float](repeating: 0, count: tensor.count) }
            var scale = Float((2.0 / Double(tensor.fanIn)).squareRoot())
            if tensor.name.hasSuffix(".b.w") { scale *= 0.1 }
            if tensor.name.hasPrefix("policy") || tensor.name.hasPrefix("value.fc2") { scale *= 0.1 }
            return (0..<tensor.count).map { _ in Float(Gaussian.sample(using: &rng)) * scale }
        }
    }

    public subscript(_ index: Int) -> [Float] { values[index] }

    // MARK: - Storage

    /// Raw little-endian floats, every tensor end to end. The architecture is
    /// stored alongside, not in here.
    public func data() -> Data {
        var data = Data(capacity: architecture.parameterCount * 4)
        for array in values {
            array.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        }
        return data
    }

    public init(architecture: NetworkArchitecture, data: Data) throws {
        let expected = architecture.parameterCount * 4
        guard data.count == expected else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "Weights are \(data.count) bytes; expected \(expected)."
            ])
        }
        var offset = 0
        var values: [[Float]] = []
        for tensor in architecture.tensors {
            let bytes = tensor.count * 4
            let array = data.subdata(in: offset..<(offset + bytes)).withUnsafeBytes {
                Array($0.bindMemory(to: Float.self))
            }
            values.append(array)
            offset += bytes
        }
        self.init(architecture: architecture, values: values)
    }
}

/// Standard normal samples from a seeded generator, for initialisation and noise.
enum Gaussian {
    static func sample(using rng: inout SeededRandomNumberGenerator) -> Double {
        // Box–Muller. The first uniform is kept off zero so the log is finite.
        let u1 = Double.random(in: Double.ulpOfOne..<1, using: &rng)
        let u2 = Double.random(in: 0..<1, using: &rng)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    /// A Gamma(shape, 1) sample, by Marsaglia and Tsang.
    static func gamma(shape: Double, using rng: inout SeededRandomNumberGenerator) -> Double {
        if shape < 1 {
            let u = Double.random(in: Double.ulpOfOne..<1, using: &rng)
            return gamma(shape: shape + 1, using: &rng) * pow(u, 1 / shape)
        }
        let d = shape - 1.0 / 3.0
        let c = 1 / (9 * d).squareRoot()
        while true {
            var x: Double
            var v: Double
            repeat {
                x = sample(using: &rng)
                v = 1 + c * x
            } while v <= 0
            v = v * v * v
            let u = Double.random(in: Double.ulpOfOne..<1, using: &rng)
            if log(u) < 0.5 * x * x + d - d * v + d * log(v) { return d * v }
        }
    }

    /// A Dirichlet(alpha, …, alpha) sample of the given length.
    static func dirichlet(count: Int, alpha: Double, using rng: inout SeededRandomNumberGenerator) -> [Double] {
        let draws = (0..<count).map { _ in gamma(shape: alpha, using: &rng) }
        let total = draws.reduce(0, +)
        guard total > 0 else { return [Double](repeating: 1 / Double(count), count: count) }
        return draws.map { $0 / total }
    }
}
