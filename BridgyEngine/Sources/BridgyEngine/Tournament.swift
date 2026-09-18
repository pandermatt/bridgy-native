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
///
/// Holds a way to *make* its engine rather than one engine, so each board size
/// gets an engine configured for that size. Building once at the largest size
/// and reusing it spread a fixed search budget thinnest exactly where games
/// were hardest.
public struct Participant: Sendable {
    public let name: String
    private let make: @Sendable (Int) -> any Engine

    /// The same engine at every size.
    public init(name: String, engine: any Engine) {
        self.name = name
        self.make = { _ in engine }
    }

    /// An engine built for each board size it plays at.
    public init(name: String, engineForSize: @escaping @Sendable (Int) -> any Engine) {
        self.name = name
        self.make = engineForSize
    }

    public func engine(forSize size: Int) -> any Engine { make(size) }
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
    ///
    /// `size` is kept for callers that want one fixed size; in a tournament each
    /// engine is rebuilt for every board size it plays.
    public static func defaultParticipants(forSize size: Int? = nil) -> [Participant] {
        Difficulty.allCases.map { level in
            if let size {
                let engine = level.tournamentEngine(forSize: size)
                return Participant(name: level.displayName, engine: engine)
            }
            return Participant(name: level.displayName) { level.tournamentEngine(forSize: $0) }
        }
    }

    /// One game to be played: who, where, and its own seed.
    struct Job: Sendable {
        let index: Int
        let size: Int
        let blue: Int
        let red: Int
        let seed: UInt64
    }

    /// Every game of the round-robin, in the order they are reported.
    static func jobs(configuration: TournamentConfiguration, participants: Int, seed: UInt64) -> [Job] {
        var jobs: [Job] = []
        for size in configuration.sizes {
            for first in 0..<participants {
                for second in (first + 1)..<participants {
                    for _ in 0..<configuration.gamesPerColour {
                        for firstPlaysBlue in [true, false] {
                            let index = jobs.count
                            jobs.append(Job(
                                index: index,
                                size: size,
                                blue: firstPlaysBlue ? first : second,
                                red: firstPlaysBlue ? second : first,
                                seed: SeededRandomNumberGenerator.mix(seed, UInt64(index))
                            ))
                        }
                    }
                }
            }
        }
        return jobs
    }

    /// Plays the round-robin, yielding each game in order as results come in.
    ///
    /// Games run in parallel, one per core. Each has its own seed derived from
    /// its position in the schedule, and results are released in that order, so
    /// a tournament gives identical results — Elo history included, which
    /// depends on order — however the work happens to be scheduled.
    public static func stream(
        configuration: TournamentConfiguration,
        participants: [Participant],
        seed: UInt64 = 0xB0A4D,
        parallelism: Int = ProcessInfo.processInfo.activeProcessorCount
    ) -> AsyncStream<Outcome> {
        let schedule = jobs(configuration: configuration, participants: participants.count, seed: seed)
        let width = max(1, parallelism)
        return AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                await withTaskGroup(of: (Int, Outcome?).self) { group in
                    var next = 0
                    // Finished games waiting for everything before them. A game
                    // with no winner is stored as nil so it still advances the
                    // cursor rather than stalling every result behind it.
                    var waiting: [Int: Outcome?] = [:]
                    var released = 0

                    func submit() {
                        guard next < schedule.count else { return }
                        let job = schedule[next]
                        next += 1
                        group.addTask {
                            if Task.isCancelled { return (job.index, nil) }
                            var rng = SeededRandomNumberGenerator(seed: job.seed)
                            let final = Match.play(
                                size: job.size,
                                blue: participants[job.blue].engine(forSize: job.size),
                                red: participants[job.red].engine(forSize: job.size),
                                rng: &rng
                            )
                            guard let winner = final.winner else { return (job.index, nil) }
                            return (job.index, Outcome(gameIndex: job.index, size: job.size,
                                                       blue: job.blue, red: job.red, winner: winner))
                        }
                    }

                    for _ in 0..<width { submit() }
                    while let (index, outcome) = await group.next() {
                        if Task.isCancelled { group.cancelAll(); break }
                        waiting.updateValue(outcome, forKey: index)
                        submit()
                        while let ready = waiting.removeValue(forKey: released) {
                            if let ready { continuation.yield(ready) }
                            released += 1
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
