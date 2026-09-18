import Accelerate

/// Runs a network on the CPU.
///
/// Training happens on the GPU, but playing does not need it: a position is one
/// small forward pass, and on the CPU the engine stays a plain `Sendable` value
/// that runs on every platform, in parallel tournament games, and gives the
/// same answer every time for the same seed. Each convolution is an im2col
/// followed by one `cblas_sgemm`.
public struct NeuralNetwork: Sendable {
    public let weights: NetworkWeights

    public init(weights: NetworkWeights) {
        self.weights = weights
    }

    /// Raw network output for one encoded position.
    public struct Output: Sendable {
        /// One logit per lattice point. Only the cells' points mean anything.
        public var logits: [Float]
        /// The position's worth to the player to move, in −1...1.
        public var value: Float

        public init(logits: [Float], value: Float) {
            self.logits = logits
            self.value = value
        }
    }

    /// What the network makes of a position.
    public struct Judgement: Sendable {
        /// Move probabilities over the legal cells, indexed by cell and summing to one.
        public var priors: [(cell: Int, prior: Float)]
        /// The position's worth to the player to move, in −1...1.
        public var value: Float
    }

    /// Priors and value for the player to move in `state`.
    public func judge(_ state: GameState, symmetry: Symmetry = .identity) -> Judgement {
        let side = BoardEncoding.side(for: state.board)
        let output = evaluate(BoardEncoding.encode(state, symmetry: symmetry), side: side)
        let map = BoardEncoding.cellMap(board: state.board, mover: state.current, symmetry: symmetry)
        let legal = state.legalMoveIndices
        guard !legal.isEmpty else { return Judgement(priors: [], value: output.value) }
        let logits = legal.map { output.logits[map[$0]] }
        let top = logits.max() ?? 0
        let exps = logits.map { expf($0 - top) }
        let total = exps.reduce(0, +)
        return Judgement(
            priors: zip(legal, exps).map { (cell: $0, prior: $1 / total) },
            value: output.value
        )
    }

    /// The forward pass, on one position encoded by `BoardEncoding`.
    public func evaluate(_ input: [Float], side: Int) -> Output {
        let arch = weights.architecture
        let c = arch.channels
        let points = side * side
        precondition(input.count == points * BoardEncoding.planes, "Input does not match the board")

        var x = [Float](repeating: 0, count: points * c)
        var h = [Float](repeating: 0, count: points * c)
        var t = [Float](repeating: 0, count: points * c)
        var columns = [Float](repeating: 0, count: points * 9 * max(c, BoardEncoding.planes))

        input.withUnsafeBufferPointer { src in
            convolve3x3(src.baseAddress!, inputs: BoardEncoding.planes, outputs: c, side: side,
                        tensor: 0, into: &x, columns: &columns)
        }
        relu(&x)

        for block in 0..<arch.blocks {
            let first = 2 + block * 4
            x.withUnsafeBufferPointer { src in
                convolve3x3(src.baseAddress!, inputs: c, outputs: c, side: side,
                            tensor: first, into: &h, columns: &columns)
            }
            relu(&h)
            h.withUnsafeBufferPointer { src in
                convolve3x3(src.baseAddress!, inputs: c, outputs: c, side: side,
                            tensor: first + 2, into: &t, columns: &columns)
            }
            x.withUnsafeMutableBufferPointer { sum in
                vDSP_vadd(sum.baseAddress!, 1, t, 1, sum.baseAddress!, 1, vDSP_Length(sum.count))
            }
            relu(&x)
        }

        let heads = 2 + arch.blocks * 4
        var logits = [Float](repeating: 0, count: points)
        dense(x, rows: points, inputs: c, outputs: 1, tensor: heads, into: &logits)

        let v = arch.valueChannels
        var reduced = [Float](repeating: 0, count: points * v)
        dense(x, rows: points, inputs: c, outputs: v, tensor: heads + 2, into: &reduced)
        relu(&reduced)
        var pooled = [Float](repeating: 0, count: v)
        for channel in 0..<v {
            var mean: Float = 0
            reduced.withUnsafeBufferPointer {
                vDSP_meanv($0.baseAddress! + channel, vDSP_Stride(v), &mean, vDSP_Length(points))
            }
            pooled[channel] = mean
        }
        var hidden = [Float](repeating: 0, count: arch.valueHidden)
        dense(pooled, rows: 1, inputs: v, outputs: arch.valueHidden, tensor: heads + 4, into: &hidden)
        relu(&hidden)
        var out = [Float](repeating: 0, count: 1)
        dense(hidden, rows: 1, inputs: arch.valueHidden, outputs: 1, tensor: heads + 6, into: &out)

        return Output(logits: logits, value: tanhf(out[0]))
    }

    // MARK: - Layers

    /// A 3×3 convolution with zero padding, stride one.
    private func convolve3x3(
        _ input: UnsafePointer<Float>,
        inputs: Int,
        outputs: Int,
        side: Int,
        tensor: Int,
        into output: inout [Float],
        columns: inout [Float]
    ) {
        let width = 9 * inputs
        columns.withUnsafeMutableBufferPointer { col in
            let base = col.baseAddress!
            for y in 0..<side {
                for x in 0..<side {
                    let row = base + (y * side + x) * width
                    for ky in 0..<3 {
                        let sy = y + ky - 1
                        for kx in 0..<3 {
                            let sx = x + kx - 1
                            let dest = row + (ky * 3 + kx) * inputs
                            if sy >= 0, sy < side, sx >= 0, sx < side {
                                dest.update(from: input + (sy * side + sx) * inputs, count: inputs)
                            } else {
                                dest.update(repeating: 0, count: inputs)
                            }
                        }
                    }
                }
            }
        }
        multiply(columns, rows: side * side, inputs: width, outputs: outputs, tensor: tensor, into: &output)
    }

    /// `input` is `rows × inputs`; the result is `rows × outputs`, bias added.
    private func dense(_ input: [Float], rows: Int, inputs: Int, outputs: Int, tensor: Int, into output: inout [Float]) {
        multiply(input, rows: rows, inputs: inputs, outputs: outputs, tensor: tensor, into: &output)
    }

    private func multiply(_ input: [Float], rows: Int, inputs: Int, outputs: Int, tensor: Int, into output: inout [Float]) {
        let w = weights[tensor]
        let b = weights[tensor + 1]
        output.withUnsafeMutableBufferPointer { out in
            for row in 0..<rows {
                (out.baseAddress! + row * outputs).update(from: b, count: outputs)
            }
            input.withUnsafeBufferPointer { a in
                w.withUnsafeBufferPointer { wb in
                    cblas_sgemm(
                        CblasRowMajor, CblasNoTrans, CblasNoTrans,
                        .init(rows), .init(outputs), .init(inputs),
                        1, a.baseAddress!, .init(inputs),
                        wb.baseAddress!, .init(outputs),
                        1, out.baseAddress!, .init(outputs)
                    )
                }
            }
        }
    }

    private func relu(_ values: inout [Float]) {
        var zero: Float = 0
        values.withUnsafeMutableBufferPointer { v in
            vDSP_vthres(v.baseAddress!, 1, &zero, v.baseAddress!, 1, vDSP_Length(v.count))
        }
    }
}
