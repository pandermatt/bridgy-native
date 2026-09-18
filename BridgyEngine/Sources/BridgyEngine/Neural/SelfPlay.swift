import Foundation

/// A network playing itself to make its own training data.
public enum SelfPlay {

    /// One position to learn from: what the search preferred there, and how the
    /// game went for the player to move.
    public struct Sample: Sendable {
        public let state: GameState
        /// Share of the root's visits per cell, indexed by cell. Zero on
        /// occupied cells.
        public let policy: [Float]
        /// +1 if the player to move went on to win, −1 if not.
        public let outcome: Float
    }

    public struct Settings: Sendable, Hashable {
        public var simulations: Int
        /// Moves played in proportion to visits before switching to the best,
        /// so games open differently and the data covers more than one line.
        public var exploratoryMoves: Int
        public var noiseAlpha: Double
        public var noiseFraction: Float

        public init(simulations: Int, exploratoryMoves: Int, noiseAlpha: Double = 0.3, noiseFraction: Float = 0.25) {
            self.simulations = simulations
            self.exploratoryMoves = exploratoryMoves
            self.noiseAlpha = noiseAlpha
            self.noiseFraction = noiseFraction
        }
    }

    /// Plays one game and returns every position in it, labelled.
    public static func game(
        network: NeuralNetwork,
        size: Int,
        settings: Settings,
        rng: inout SeededRandomNumberGenerator
    ) -> [Sample] {
        let engine = NeuralMCTSEngine(network: network, simulations: settings.simulations)
        var state = GameState(size: size)
        var pending: [(state: GameState, policy: [Float])] = []

        while !state.isOver {
            if Task.isCancelled { return [] }
            let result = engine.search(
                state,
                rng: &rng,
                rootNoise: (settings.noiseAlpha, settings.noiseFraction)
            )
            var policy = [Float](repeating: 0, count: state.board.cellCount)
            let total = Float(result.visits.reduce(0) { $0 + $1.count })
            for entry in result.visits where total > 0 {
                policy[entry.cell] = Float(entry.count) / total
            }
            pending.append((state, policy))

            let temperature: Float = state.moveCount < settings.exploratoryMoves ? 1 : 0
            guard let cell = NeuralMCTSEngine.pick(result.visits, temperature: temperature, rng: &rng) else { break }
            state.apply(state.board.move(at: cell))
        }

        guard let winner = state.winner else { return [] }
        return pending.map { entry in
            Sample(state: entry.state, policy: entry.policy, outcome: entry.state.current == winner ? 1 : -1)
        }
    }
}

/// Two engines playing a short match, for deciding which is stronger.
public enum Arena {

    /// The first engine's share of wins, over `games` games split evenly
    /// between the colours. Bridg-It favours whoever moves first, so one-sided
    /// colours would measure the colour rather than the engine.
    public static func score(
        of first: any Engine,
        against second: any Engine,
        size: Int,
        games: Int,
        seed: UInt64,
        parallelism: Int = ProcessInfo.processInfo.activeProcessorCount
    ) async -> Double {
        guard games > 0 else { return 0 }
        let wins = await withTaskGroup(of: Int.self) { group in
            var next = 0
            var total = 0
            func submit() {
                guard next < games else { return }
                let index = next
                next += 1
                group.addTask {
                    if Task.isCancelled { return 0 }
                    var rng = SeededRandomNumberGenerator(seed: SeededRandomNumberGenerator.mix(seed, UInt64(index)))
                    let firstIsBlue = index % 2 == 0
                    let final = Match.play(
                        size: size,
                        blue: firstIsBlue ? first : second,
                        red: firstIsBlue ? second : first,
                        rng: &rng
                    )
                    return final.winner == (firstIsBlue ? .blue : .red) ? 1 : 0
                }
            }
            for _ in 0..<max(1, parallelism) { submit() }
            while let won = await group.next() {
                total += won
                submit()
            }
            return total
        }
        return Double(wins) / Double(games)
    }
}
