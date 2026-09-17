import Foundation

/// Settings for a round-robin between every engine.
public struct TournamentConfiguration: Sendable, Hashable, Codable {
    public var minimumSize: Int
    public var maximumSize: Int
    /// Games each pairing plays *in each colour*, at each board size.
    public var gamesPerColour: Int

    public init(minimumSize: Int = 4, maximumSize: Int = 6, gamesPerColour: Int = 5) {
        self.minimumSize = minimumSize
        self.maximumSize = maximumSize
        self.gamesPerColour = gamesPerColour
    }

    public var sizes: [Int] { Array(min(minimumSize, maximumSize)...max(minimumSize, maximumSize)) }

    public func totalGames(participants: Int) -> Int {
        let pairings = participants * (participants - 1) / 2
        return pairings * sizes.count * gamesPerColour * 2
    }
}

/// One engine in the field.
public struct Participant: Sendable {
    public let name: String
    public let engine: any Engine

    public init(name: String, engine: any Engine) {
        self.name = name
        self.engine = engine
    }
}

/// Runs every engine against every other, reporting each game as it finishes.
public enum Tournament {

    /// The result of a single game.
    public struct Outcome: Sendable, Hashable {
        public let gameIndex: Int
        public let size: Int
        public let blue: Int
        public let red: Int
        public let winner: Player

        /// Index of the participant that won.
        public var winnerIndex: Int { winner == .blue ? blue : red }
        public var loserIndex: Int { winner == .blue ? red : blue }
    }

    /// One engine per difficulty, with every engine's cost bounded.
    public static func defaultParticipants(forSize size: Int) -> [Participant] {
        Difficulty.allCases.map {
            Participant(name: $0.displayName, engine: $0.tournamentEngine(forSize: size))
        }
    }

    /// Plays the round-robin, yielding each game as it completes.
    ///
    /// Streaming rather than returning at the end is what lets the charts fill
    /// in while the tournament runs. Cancelling the consuming task stops the
    /// work — the games are played on a detached task that checks between each.
    public static func stream(
        configuration: TournamentConfiguration,
        participants: [Participant],
        seed: UInt64 = 0xB0A4D
    ) -> AsyncStream<Outcome> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                var rng = SeededRandomNumberGenerator(seed: seed)
                var gameIndex = 0
                let count = participants.count

                outer: for size in configuration.sizes {
                    for first in 0..<count {
                        for second in (first + 1)..<count {
                            for _ in 0..<configuration.gamesPerColour {
                                for firstPlaysBlue in [true, false] {
                                    if Task.isCancelled { break outer }

                                    let blueIndex = firstPlaysBlue ? first : second
                                    let redIndex = firstPlaysBlue ? second : first
                                    let final = Match.play(
                                        size: size,
                                        blue: participants[blueIndex].engine,
                                        red: participants[redIndex].engine,
                                        rng: &rng
                                    )
                                    guard let winner = final.winner else { continue }

                                    continuation.yield(
                                        Outcome(
                                            gameIndex: gameIndex,
                                            size: size,
                                            blue: blueIndex,
                                            red: redIndex,
                                            winner: winner
                                        )
                                    )
                                    gameIndex += 1
                                }
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
