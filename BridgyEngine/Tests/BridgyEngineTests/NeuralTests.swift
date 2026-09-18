import Foundation
import Testing
@testable import BridgyEngine
@testable import BridgyTraining

/// A position reached by playing `count` random moves, without anyone winning.
private func randomPosition(size: Int, moves count: Int, seed: UInt64) -> GameState {
    var rng = SeededRandomNumberGenerator(seed: seed)
    var state = GameState(size: size)
    for _ in 0..<count {
        let legal = state.legalMoves.filter { !state.wouldWin($0, for: state.current) }
        guard let move = legal.randomElement(using: &rng) else { break }
        state.apply(move)
    }
    return state
}

private func plane(_ encoded: [Float], _ index: Int) -> Set<Int> {
    Set(stride(from: 0, to: encoded.count, by: BoardEncoding.planes).compactMap { base in
        encoded[base + index] == 1 ? base / BoardEncoding.planes : nil
    })
}

@Suite("Board encoding")
struct BoardEncodingTests {

    @Test("Every cell is exactly one of mine, theirs or empty, and decodes back", arguments: [2, 3, 5, 8])
    func roundTrip(size: Int) {
        for seed in 0..<10 as Range<UInt64> {
            let state = randomPosition(size: size, moves: Int(seed) * 2 + 1, seed: seed)
            for symmetry in Symmetry.allCases {
                let encoded = BoardEncoding.encode(state, symmetry: symmetry)
                let map = BoardEncoding.cellMap(board: state.board, mover: state.current, symmetry: symmetry)
                #expect(Set(map).count == map.count, "Two cells share a lattice point")
                for cell in 0..<state.board.cellCount {
                    let at = map[cell] * BoardEncoding.planes
                    let flags = (0..<3).map { encoded[at + $0] }
                    #expect(flags.reduce(0, +) == 1)
                    let decoded: Player? = flags[0] == 1 ? state.current : flags[1] == 1 ? state.current.opponent : nil
                    #expect(decoded == state.cells[cell])
                    #expect(encoded[at + 3] == 0 && encoded[at + 4] == 0, "A cell is also a dot")
                }
            }
        }
    }

    @Test("Across is shown as if it were Down: its chain runs top to bottom")
    func acrossIsTransposed() {
        let size = 5
        let board = Board(size: size)
        let row = 2
        // Across builds a row of bridges straight across the middle, short of
        // winning; Down builds the same thing as a column, with Down to move.
        let chain = (0..<(size - 1)).map { Move(kind: .v, row: row, col: $0) }
        let column = (0..<(size - 1)).map { Move(kind: .v, row: $0, col: row) }
        let filler = [Move(kind: .h, row: 0, col: 0), Move(kind: .h, row: 3, col: 3),
                      Move(kind: .h, row: 0, col: 3), Move(kind: .h, row: 3, col: 0),
                      Move(kind: .h, row: 1, col: 0)]

        var across = GameState(board: board)
        for (index, move) in chain.enumerated() {
            across.apply(filler[index])
            across.apply(move)
        }
        across.apply(filler[4])
        #expect(across.current == .red)

        var down = GameState(board: board)
        for (index, move) in column.enumerated() {
            down.apply(move)
            down.apply(filler[index])
        }
        #expect(down.current == .blue)

        let a = BoardEncoding.encode(across)
        let d = BoardEncoding.encode(down)
        #expect(plane(a, 0) == plane(d, 0), "Own bridges differ")
        for p in [3, 4, 5] { #expect(plane(a, p) == plane(d, p), "Plane \(p) differs") }
        // And that column really is vertical in the network's view.
        let side = BoardEncoding.side(for: board)
        #expect(Set(plane(a, 0).map { $0 % side }).count == 1)
    }

    @Test("Symmetries keep each player's goal and move legal moves onto legal moves")
    func symmetries() {
        let state = randomPosition(size: 6, moves: 9, seed: 42)
        let board = state.board
        let side = BoardEncoding.side(for: board)
        let identity = BoardEncoding.encode(state)
        for symmetry in Symmetry.allCases {
            let turned = BoardEncoding.encode(state, symmetry: symmetry)
            // Same pieces, same dots, possibly elsewhere.
            for p in 0..<BoardEncoding.planes {
                #expect(plane(turned, p).count == plane(identity, p).count)
            }
            // Own dots still sit on the own goal rows, top and bottom.
            let ownDots = plane(turned, 3)
            let onGoal = ownDots.filter { $0 / side == 0 || $0 / side == side - 1 }
            #expect(onGoal.count == 2 * board.size)
            // Every legal move lands on an empty-cell point.
            let map = BoardEncoding.cellMap(board: board, mover: state.current, symmetry: symmetry)
            let empty = plane(turned, 2)
            for cell in state.legalMoveIndices { #expect(empty.contains(map[cell])) }
        }
    }
}

@Suite("Neural network")
struct NeuralNetworkTests {
    let architecture = NetworkArchitecture(channels: 8, blocks: 2, valueChannels: 4, valueHidden: 8)

    @Test("Weights survive being written and read back")
    func weightsRoundTrip() throws {
        let weights = NetworkWeights(random: architecture, seed: 7)
        let back = try NetworkWeights(architecture: architecture, data: weights.data())
        #expect(back == weights)
    }

    @Test("The CPU forward pass matches the GPU's")
    func cpuMatchesGPU() throws {
        let weights = NetworkWeights(random: architecture, seed: 11)
        let state = randomPosition(size: 4, moves: 5, seed: 3)
        let input = BoardEncoding.encode(state)
        let cpu = NeuralNetwork(weights: weights).evaluate(input, side: BoardEncoding.side(for: state.board))
        let trainer = try GraphTrainer(weights: weights, boardSize: 4, batchSize: 2, weightDecay: 0)
        let gpu = trainer.evaluate(input)
        #expect(cpu.logits.count == gpu.logits.count)
        let worst = zip(cpu.logits, gpu.logits).map { abs($0 - $1) }.max() ?? 0
        #expect(worst < 1e-3, "Logits differ by \(worst)")
        #expect(abs(cpu.value - gpu.value) < 1e-3)
    }

    @Test("Training can memorise a small batch — the gradients are wired right")
    func overfits() throws {
        let size = 4
        var buffer = ReplayBuffer(capacity: 100)
        var rng = SeededRandomNumberGenerator(seed: 5)
        let samples = (0..<16).map { index -> SelfPlay.Sample in
            let state = randomPosition(size: size, moves: index % 7, seed: UInt64(index))
            var policy = [Float](repeating: 0, count: state.board.cellCount)
            let target = state.legalMoveIndices.randomElement(using: &rng)!
            policy[target] = 1
            return SelfPlay.Sample(state: state, policy: policy, outcome: index % 2 == 0 ? 1 : -1)
        }
        buffer.append(samples)
        // Identity only: the same 16 positions every step.
        let batch = batchOf(samples, size: size)
        let trainer = try GraphTrainer(
            weights: NetworkWeights(random: NetworkArchitecture(channels: 16, blocks: 2), seed: 1),
            boardSize: size, batchSize: 16, weightDecay: 0
        )
        let first = trainer.train(batch, learningRate: 0.003)
        var last = first
        for _ in 0..<400 { last = trainer.train(batch, learningRate: 0.003) }
        #expect(last.policy < first.policy * 0.2, "Policy loss \(first.policy) → \(last.policy)")
        #expect(last.value < first.value * 0.2, "Value loss \(first.value) → \(last.value)")

        // And the weights read back from the GPU give the same answers on the CPU.
        let network = NeuralNetwork(weights: trainer.weights())
        let judged = network.judge(samples[0].state)
        let best = judged.priors.max { $0.prior < $1.prior }!.cell
        #expect(samples[0].policy[best] == 1)
    }

    private func batchOf(_ samples: [SelfPlay.Sample], size: Int) -> TrainingBatch {
        let board = Board(size: size)
        let side = BoardEncoding.side(for: board)
        let points = side * side
        var batch = TrainingBatch(count: samples.count, inputs: [], policy: [], legal: [], outcome: [])
        for sample in samples {
            batch.inputs += BoardEncoding.encode(sample.state)
            var policy = [Float](repeating: 0, count: points)
            var legal = [Float](repeating: 0, count: points)
            let map = BoardEncoding.cellMap(board: board, mover: sample.state.current, symmetry: .identity)
            for cell in sample.state.legalMoveIndices {
                legal[map[cell]] = 1
                policy[map[cell]] = sample.policy[cell]
            }
            batch.policy += policy
            batch.legal += legal
            batch.outcome.append(sample.outcome)
        }
        return batch
    }
}

@Suite("Neural search")
struct NeuralSearchTests {
    let network = NeuralNetwork(weights: NetworkWeights(random: NetworkArchitecture(channels: 8, blocks: 1), seed: 2))

    @Test("Only ever plays legal moves", arguments: [2, 4, 6])
    func legal(size: Int) {
        let engine = NeuralMCTSEngine(network: network, simulations: 16, exploratoryMoves: 3)
        var rng = SeededRandomNumberGenerator(seed: UInt64(size))
        for game in 0..<3 {
            var state = GameState(size: size)
            while !state.isOver {
                let move = state.current == (game % 2 == 0 ? .blue : .red)
                    ? engine.chooseMove(in: state, rng: &rng)
                    : RandomEngine().chooseMove(in: state, rng: &rng)
                #expect(move.map(state.isLegal) == true)
                guard let move else { break }
                state.apply(move)
            }
        }
    }

    @Test("Self-play labels each position with how it went for the side to move")
    func selfPlayLabels() {
        var rng = SeededRandomNumberGenerator(seed: 9)
        let samples = SelfPlay.game(
            network: network, size: 4,
            settings: .init(simulations: 8, exploratoryMoves: 4), rng: &rng
        )
        #expect(!samples.isEmpty)
        for (a, b) in zip(samples, samples.dropFirst()) {
            #expect(a.outcome == -b.outcome, "Consecutive positions belong to opposite sides")
        }
        for sample in samples {
            #expect(abs(sample.policy.reduce(0, +) - 1) < 1e-4)
        }
    }

    @Test("The gate turns away a clearly weaker network")
    func gateRejects() async {
        let untrained = NeuralMCTSEngine(network: network, simulations: 1)
        let strong = MCTSEngine(iterations: 400)
        let score = await Arena.score(of: untrained, against: strong, size: 5, games: 12, seed: 1)
        #expect(score < TrainingParameters().gateThreshold)
    }
}

/// A real training run. Minutes, not seconds, so opt in:
///   BRIDGY_TRAIN=1 swift test --filter TrainingRunTests
@Suite("Training run", .enabled(if: ProcessInfo.processInfo.environment["BRIDGY_TRAIN"] != nil))
struct TrainingRunTests {

    /// Against Random the untrained network already wins most games — its
    /// win-or-block check does that on its own — so the yardstick is Hard.
    @Test("Ten rounds at 5×5 make it clearly stronger against Hard")
    func improves() async throws {
        var p = TrainingParameters()
        p.rounds = 10
        p.benchmarkGames = 0

        var latest: NetworkWeights?
        for await event in Training.run(parameters: p) {
            switch event {
            case .checkpoint(_, _, let weights): latest = weights
            case .failed(let message): Issue.record("\(message)")
            default: break
            }
        }
        let trained = try #require(latest)
        func score(_ weights: NetworkWeights) async -> Double {
            await Arena.score(
                of: NeuralMCTSEngine(network: NeuralNetwork(weights: weights), simulations: p.simulations),
                against: Difficulty.hard.tournamentEngine(forSize: p.boardSize),
                size: p.boardSize, games: 40, seed: 3
            )
        }
        let before = await score(NetworkWeights(random: p.architecture, seed: 0x7EA1))
        let after = await score(trained)
        print("vs Hard at 5×5: untrained \(before), trained \(after)")
        #expect(after >= before + 0.25)
    }
}
