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

    /// Total games the run will play, for the progress bar.
    public func totalGames(participants: Int) -> Int {
        let pairings = participants * (participants - 1) / 2
        return pairings * sizes.count * gamesPerColour * 2
    }
}

/// Outcome of a round-robin.
public struct TournamentResult: Sendable, Hashable, Codable {
    public let participants: [String]
    /// `winRate[i][j]` is the share of games `i` won against `j`, over both colours.
    public let winRate: [[Double]]
    public let configuration: TournamentConfiguration

    public var averages: [Double] {
        winRate.indices.map { row in
            let others = winRate[row].indices.filter { $0 != row }
            guard !others.isEmpty else { return 0 }
            return others.reduce(0.0) { $0 + winRate[row][$1] } / Double(others.count)
        }
    }

    /// Ranking, strongest first.
    public var standings: [(name: String, average: Double)] {
        let scores = averages
        return participants.indices
            .map { (participants[$0], scores[$0]) }
            .sorted { $0.1 > $1.1 }
    }

    /// Semicolon-separated CSV, as the original produced — but with a board-size
    /// column that actually varies, which the Java version's did not.
    public func csv() -> String {
        var lines: [String] = []
        lines.append("Bridgy tournament")
        lines.append("Board sizes;\(configuration.sizes.map(String.init).joined(separator: " "))")
        lines.append("Games per colour per size;\(configuration.gamesPerColour)")
        lines.append("Total games;\(configuration.totalGames(participants: participants.count))")
        lines.append("")
        lines.append("Win rate of the row engine against the column engine, both colours combined.")
        lines.append("Engine;" + participants.joined(separator: ";") + ";Average")
        let scores = averages
        for (row, name) in participants.enumerated() {
            let cells = winRate[row].indices.map { column -> String in
                column == row ? "-" : String(format: "%.1f%%", winRate[row][column] * 100)
            }
            lines.append("\(name);" + cells.joined(separator: ";") + String(format: ";%.1f%%", scores[row] * 100))
        }
        return lines.joined(separator: "\n")
    }
}

/// Runs every engine against every other.
public enum Tournament {

    /// The default field: one engine per difficulty level.
    public static func defaultParticipants(forSize size: Int) -> [(name: String, engine: any Engine)] {
        Difficulty.allCases.map { ($0.displayName, $0.tournamentEngine(forSize: size)) }
    }

    /// Plays the round-robin, reporting progress as a fraction.
    ///
    /// Honours cancellation between games, so leaving the screen stops the work
    /// rather than letting it grind on in the background.
    public static func run(
        configuration: TournamentConfiguration,
        participants: [(name: String, engine: any Engine)],
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async -> TournamentResult? {
        let count = participants.count
        guard count > 1 else { return nil }

        var wins = [[Int]](repeating: [Int](repeating: 0, count: count), count: count)
        var played = [[Int]](repeating: [Int](repeating: 0, count: count), count: count)

        let total = max(configuration.totalGames(participants: count), 1)
        var completed = 0
        var rng = SeededRandomNumberGenerator(seed: 0xB0A4D)

        for size in configuration.sizes {
            for first in 0..<count {
                for second in (first + 1)..<count {
                    for _ in 0..<configuration.gamesPerColour {
                        for firstPlaysBlue in [true, false] {
                            if Task.isCancelled { return nil }

                            let blue = firstPlaysBlue ? participants[first].engine : participants[second].engine
                            let red = firstPlaysBlue ? participants[second].engine : participants[first].engine
                            let winner = Match.play(size: size, blue: blue, red: red, rng: &rng).winner

                            let firstWon = firstPlaysBlue ? (winner == .blue) : (winner == .red)
                            played[first][second] += 1
                            played[second][first] += 1
                            if firstWon { wins[first][second] += 1 } else { wins[second][first] += 1 }

                            completed += 1
                            onProgress?(Double(completed) / Double(total))
                            await Task.yield()
                        }
                    }
                }
            }
        }

        let rates = (0..<count).map { row in
            (0..<count).map { column -> Double in
                guard played[row][column] > 0 else { return 0 }
                return Double(wins[row][column]) / Double(played[row][column])
            }
        }
        return TournamentResult(
            participants: participants.map(\.name),
            winRate: rates,
            configuration: configuration
        )
    }
}
