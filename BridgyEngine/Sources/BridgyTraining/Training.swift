import BridgyEngine
import Foundation

/// Everything someone can set before training an agent.
public struct TrainingParameters: Sendable, Hashable, Codable {
    /// The board it practises on. It will play other sizes, best this one.
    public var boardSize = 5
    public var channels = 32
    public var blocks = 4
    public var learningRate = 0.002
    public var batchSize = 64
    public var weightDecay = 0.0001
    /// Search per move in self-play, the gate and the benchmarks.
    public var simulations = 48
    public var gamesPerRound = 48
    public var stepsPerRound = 400
    public var rounds = 20
    /// Games the new network plays the current best before it is kept.
    public var gateGames = 24
    /// Share of those it must win.
    public var gateThreshold = 0.55
    public var benchmarkGames = 20
    public var replayCapacity = 40_000

    public init() {}

    public var architecture: NetworkArchitecture {
        NetworkArchitecture(channels: channels, blocks: blocks)
    }
}

/// Something that happened while training, for the live view.
public enum TrainingEvent: Sendable {
    case selfPlay(round: Int, finished: Int, of: Int)
    case loss(step: Int, policy: Float, value: Float)
    /// The new network against the best so far, and whether it replaced it.
    case gate(round: Int, score: Double, accepted: Bool)
    /// The best network so far against a fixed opponent.
    case benchmark(round: Int, opponent: String, score: Double)
    /// The best network so far, worth saving.
    case checkpoint(round: Int, steps: Int, weights: NetworkWeights)
    case failed(String)
}

/// Lets the screen pause a run between steps.
public actor TrainingControl {
    private var paused = false

    public init() {}

    public func setPaused(_ value: Bool) { paused = value }
    public var isPaused: Bool { paused }

    func waitWhilePaused() async {
        while paused, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}

/// Positions from recent self-play, drawn from at random to make batches.
struct ReplayBuffer {
    private var samples: [SelfPlay.Sample] = []
    private var next = 0
    let capacity: Int

    init(capacity: Int) { self.capacity = max(1, capacity) }

    var count: Int { samples.count }

    mutating func append(_ new: [SelfPlay.Sample]) {
        for sample in new {
            if samples.count < capacity {
                samples.append(sample)
            } else {
                samples[next] = sample
                next = (next + 1) % capacity
            }
        }
    }

    /// A batch with each position turned by a random one of the four
    /// symmetries — four times the data for nothing.
    func batch(size: Int, boardSize: Int, rng: inout SeededRandomNumberGenerator) -> TrainingBatch {
        let board = Board(size: boardSize)
        let side = BoardEncoding.side(for: board)
        let points = side * side
        let stride = points * BoardEncoding.planes
        var batch = TrainingBatch(
            count: size,
            inputs: [Float](repeating: 0, count: size * stride),
            policy: [Float](repeating: 0, count: size * points),
            legal: [Float](repeating: 0, count: size * points),
            outcome: [Float](repeating: 0, count: size)
        )
        for row in 0..<size {
            let sample = samples[Int.random(in: 0..<samples.count, using: &rng)]
            let symmetry = Symmetry.allCases.randomElement(using: &rng) ?? .identity
            batch.inputs.withUnsafeMutableBufferPointer {
                BoardEncoding.encode(sample.state, symmetry: symmetry, into: $0.baseAddress! + row * stride)
            }
            let map = BoardEncoding.cellMap(board: board, mover: sample.state.current, symmetry: symmetry)
            for cell in 0..<board.cellCount where sample.state.cells[cell] == nil {
                batch.legal[row * points + map[cell]] = 1
                batch.policy[row * points + map[cell]] = sample.policy[cell]
            }
            batch.outcome[row] = sample.outcome
        }
        return batch
    }
}

/// The AlphaZero loop: play yourself, learn from it, keep the result only if it
/// beats what you had.
public enum Training {

    public static func run(
        parameters: TrainingParameters,
        from start: NetworkWeights? = nil,
        seed: UInt64 = 0x7EA1,
        control: TrainingControl = TrainingControl()
    ) -> AsyncStream<TrainingEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await loop(parameters: parameters, start: start, seed: seed, control: control) {
                    continuation.yield($0)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func loop(
        parameters p: TrainingParameters,
        start: NetworkWeights?,
        seed: UInt64,
        control: TrainingControl,
        emit: (TrainingEvent) -> Void
    ) async {
        var rng = SeededRandomNumberGenerator(seed: seed)
        var best = start ?? NetworkWeights(random: p.architecture, seed: seed)
        let trainer: GraphTrainer
        do {
            trainer = try GraphTrainer(
                weights: best,
                boardSize: p.boardSize,
                batchSize: p.batchSize,
                weightDecay: Float(p.weightDecay)
            )
        } catch {
            emit(.failed(error.localizedDescription))
            return
        }

        var buffer = ReplayBuffer(capacity: p.replayCapacity)
        var steps = 0
        let settings = SelfPlay.Settings(simulations: p.simulations, exploratoryMoves: max(2, p.boardSize - 1))

        for round in 1...max(1, p.rounds) {
            await control.waitWhilePaused()
            if Task.isCancelled { return }

            // Self-play, with the best network so far, one game per core.
            let network = NeuralNetwork(weights: best)
            let roundSeed = SeededRandomNumberGenerator.mix(seed, UInt64(round))
            emit(.selfPlay(round: round, finished: 0, of: p.gamesPerRound))
            // Collected in whatever order they finish, then put back in game
            // order, so a run is reproducible from its seed.
            let games = await withTaskGroup(of: (Int, [SelfPlay.Sample]).self) { group in
                for game in 0..<p.gamesPerRound {
                    group.addTask {
                        var gameRng = SeededRandomNumberGenerator(seed: SeededRandomNumberGenerator.mix(roundSeed, UInt64(game)))
                        return (game, SelfPlay.game(network: network, size: p.boardSize, settings: settings, rng: &gameRng))
                    }
                }
                var all: [(Int, [SelfPlay.Sample])] = []
                for await result in group {
                    all.append(result)
                    emit(.selfPlay(round: round, finished: all.count, of: p.gamesPerRound))
                }
                return all.sorted { $0.0 < $1.0 }.map(\.1)
            }
            if Task.isCancelled { return }
            for samples in games { buffer.append(samples) }

            // Learning, on the GPU.
            for _ in 0..<p.stepsPerRound {
                await control.waitWhilePaused()
                if Task.isCancelled { return }
                let batch = buffer.batch(size: p.batchSize, boardSize: p.boardSize, rng: &rng)
                let losses = trainer.train(batch, learningRate: Float(p.learningRate))
                steps += 1
                emit(.loss(step: steps, policy: losses.policy, value: losses.value))
            }

            // The gate.
            let candidate = trainer.weights()
            let score = await Arena.score(
                of: engine(candidate, p),
                against: engine(best, p),
                size: p.boardSize,
                games: p.gateGames,
                seed: SeededRandomNumberGenerator.mix(roundSeed, 0xA7E)
            )
            if Task.isCancelled { return }
            let accepted = score >= p.gateThreshold
            emit(.gate(round: round, score: score, accepted: accepted))
            if accepted {
                best = candidate
                emit(.checkpoint(round: round, steps: steps, weights: best))
            }

            // How the best so far fares against opponents people know.
            for (index, level) in [Difficulty.easy, .medium, .hard].enumerated() {
                let versus = await Arena.score(
                    of: engine(best, p),
                    against: level.tournamentEngine(forSize: p.boardSize),
                    size: p.boardSize,
                    games: p.benchmarkGames,
                    seed: SeededRandomNumberGenerator.mix(roundSeed, UInt64(0xBE0 + index))
                )
                if Task.isCancelled { return }
                emit(.benchmark(round: round, opponent: level.displayName, score: versus))
            }
        }
    }

    static func engine(_ weights: NetworkWeights, _ p: TrainingParameters) -> NeuralMCTSEngine {
        NeuralMCTSEngine(network: NeuralNetwork(weights: weights), simulations: p.simulations, exploratoryMoves: 2)
    }
}
