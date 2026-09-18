import Foundation

/// Accumulates tournament outcomes into everything worth plotting.
///
/// Folding game by game rather than summarising at the end is what makes the
/// charts live, and it keeps the statistics out of the UI where they can be
/// tested.
public struct TournamentAnalysis: Sendable {

    /// Wins out of games, with the interval that says how much to trust it.
    public struct Record: Sendable, Hashable {
        public let wins: Int
        public let games: Int

        public init(wins: Int, games: Int) {
            self.wins = wins
            self.games = games
        }

        public var rate: Double { games > 0 ? Double(wins) / Double(games) : 0 }
        public var interval: ConfidenceInterval { Statistics.wilsonInterval(wins: wins, total: games) }
        public var isEmpty: Bool { games == 0 }
    }

    /// One engine's rating after a given number of games.
    public struct EloSample: Sendable, Hashable, Identifiable {
        public let id: Int
        public let games: Int
        public let participant: String
        public let rating: Double
    }

    /// One engine's win rate at one board size.
    public struct SizePoint: Sendable, Hashable, Identifiable {
        public let id: Int
        public let participant: String
        public let size: Int
        public let record: Record
    }

    /// Blue's win rate at one board size, over every pairing.
    public struct FirstPlayerPoint: Sendable, Hashable, Identifiable {
        public var id: Int { size }
        public let size: Int
        public let record: Record
    }

    public let participants: [String]
    public let configuration: TournamentConfiguration
    public private(set) var gamesPlayed = 0
    public private(set) var elo: EloRating
    public private(set) var eloHistory: [EloSample] = []

    private var wins: [[Int]]
    private var played: [[Int]]
    private var sizeWins: [Int: [Int]] = [:]
    private var sizePlayed: [Int: [Int]] = [:]
    private var blueWins: [Int: Int] = [:]
    private var blueGames: [Int: Int] = [:]
    /// Wins and games by colour, then size, then participant. Bridg-It is not
    /// colour-symmetric — the first player can always win — so a single rate
    /// hides the thing that matters most: Perfect never loses as Down and has
    /// no perfect strategy as Across, and only the split shows that.
    private var sideWins: [Player: [Int: [Int]]] = [:]
    private var sidePlayed: [Player: [Int: [Int]]] = [:]
    /// Keeps the rating chart to roughly 120 points per engine however long the run.
    private let sampleEvery: Int

    public init(participants: [String], configuration: TournamentConfiguration) {
        self.participants = participants
        self.configuration = configuration
        let count = participants.count
        self.wins = Array(repeating: Array(repeating: 0, count: count), count: count)
        self.played = Array(repeating: Array(repeating: 0, count: count), count: count)
        self.elo = EloRating(count: count)
        let total = max(configuration.totalGames(participants: count), 1)
        self.sampleEvery = max(1, total / 120)
        for size in configuration.sizes {
            sizeWins[size] = Array(repeating: 0, count: count)
            sizePlayed[size] = Array(repeating: 0, count: count)
            blueWins[size] = 0
            blueGames[size] = 0
            for side in Player.allCases {
                sideWins[side, default: [:]][size] = Array(repeating: 0, count: count)
                sidePlayed[side, default: [:]][size] = Array(repeating: 0, count: count)
            }
        }
        appendEloSample()
    }

    public mutating func record(_ outcome: Tournament.Outcome) {
        let winner = outcome.winnerIndex
        let loser = outcome.loserIndex

        wins[winner][loser] += 1
        played[winner][loser] += 1
        played[loser][winner] += 1

        sizeWins[outcome.size]?[winner] += 1
        sizePlayed[outcome.size]?[winner] += 1
        sizePlayed[outcome.size]?[loser] += 1

        sidePlayed[.blue]?[outcome.size]?[outcome.blue] += 1
        sidePlayed[.red]?[outcome.size]?[outcome.red] += 1
        sideWins[outcome.winner]?[outcome.size]?[winner] += 1

        blueGames[outcome.size, default: 0] += 1
        if outcome.winner == .blue { blueWins[outcome.size, default: 0] += 1 }

        elo.record(winner: winner, loser: loser)
        gamesPlayed += 1

        if gamesPlayed % sampleEvery == 0 { appendEloSample() }
    }

    /// Call once the run ends so the chart reaches the final ratings.
    public mutating func finish() {
        appendEloSample()
    }

    private mutating func appendEloSample() {
        for (index, name) in participants.enumerated() {
            eloHistory.append(
                EloSample(
                    id: gamesPlayed * 1_000 + index,
                    games: gamesPlayed,
                    participant: name,
                    rating: elo[index]
                )
            )
        }
    }

    // MARK: - Readouts

    public func head(_ row: Int, against column: Int) -> Record {
        Record(wins: wins[row][column], games: played[row][column])
    }

    public func record(of participant: Int, atSize size: Int) -> Record {
        Record(
            wins: sizeWins[size]?[participant] ?? 0,
            games: sizePlayed[size]?[participant] ?? 0
        )
    }

    /// One participant's record at one size playing one colour, or both colours
    /// together when `side` is nil.
    public func record(of participant: Int, atSize size: Int, as side: Player?) -> Record {
        guard let side else { return record(of: participant, atSize: size) }
        return Record(
            wins: sideWins[side]?[size]?[participant] ?? 0,
            games: sidePlayed[side]?[size]?[participant] ?? 0
        )
    }

    /// One participant's record over every size, playing one colour.
    public func record(of participant: Int, as side: Player) -> Record {
        configuration.sizes.reduce(Record(wins: 0, games: 0)) { total, size in
            let r = record(of: participant, atSize: size, as: side)
            return Record(wins: total.wins + r.wins, games: total.games + r.games)
        }
    }

    public func firstPlayerRecord(atSize size: Int) -> Record {
        Record(wins: blueWins[size] ?? 0, games: blueGames[size] ?? 0)
    }

    public var overall: [Record] {
        participants.indices.map { index in
            let w = participants.indices.reduce(0) { $0 + wins[index][$1] }
            let g = participants.indices.reduce(0) { $0 + played[index][$1] }
            return Record(wins: w, games: g)
        }
    }

    /// Strongest first, by rating.
    public var standings: [(name: String, rating: Double, record: Record)] {
        let records = overall
        return participants.indices
            .map { (participants[$0], elo[$0], records[$0]) }
            .sorted { $0.1 > $1.1 }
    }

    public var sizePoints: [SizePoint] { sizePoints(as: nil) }

    /// Win rate by board size, for one colour or both.
    public func sizePoints(as side: Player?) -> [SizePoint] {
        var points: [SizePoint] = []
        for (sizeIndex, size) in configuration.sizes.enumerated() {
            for (index, name) in participants.enumerated() {
                let record = self.record(of: index, atSize: size, as: side)
                guard !record.isEmpty else { continue }
                points.append(
                    SizePoint(
                        id: sizeIndex * 1_000 + index,
                        participant: name,
                        size: size,
                        record: record
                    )
                )
            }
        }
        return points
    }

    public var firstPlayerPoints: [FirstPlayerPoint] {
        configuration.sizes.compactMap { size in
            let record = firstPlayerRecord(atSize: size)
            guard !record.isEmpty else { return nil }
            return FirstPlayerPoint(size: size, record: record)
        }
    }

    // MARK: - Export

    /// Semicolon-separated, with the intervals and breakdowns included — the
    /// point being that someone can check the conclusions rather than take them.
    public func csv() -> String {
        var lines: [String] = []
        lines.append("Bridgy tournament")
        lines.append("Board sizes;\(configuration.sizes.map(String.init).joined(separator: " "))")
        lines.append("Games per colour per size;\(configuration.gamesPerColour)")
        lines.append("Games played;\(gamesPlayed)")
        lines.append("Interval;Wilson score, 95%")
        lines.append("")

        lines.append("Standings")
        lines.append("Engine;Elo;Wins;Games;Win rate;CI low;CI high")
        for entry in standings {
            let r = entry.record
            lines.append(
                [
                    entry.name,
                    String(format: "%.0f", entry.rating),
                    "\(r.wins)", "\(r.games)",
                    String(format: "%.3f", r.rate),
                    String(format: "%.3f", r.interval.low),
                    String(format: "%.3f", r.interval.high)
                ].joined(separator: ";")
            )
        }
        lines.append("")

        lines.append("Head to head (row against column): rate [CI low, CI high] over n games")
        lines.append("Engine;" + participants.joined(separator: ";"))
        for (row, name) in participants.enumerated() {
            let cells = participants.indices.map { column -> String in
                guard column != row else { return "-" }
                let r = head(row, against: column)
                return String(format: "%.3f [%.3f, %.3f] n=%d", r.rate, r.interval.low, r.interval.high, r.games)
            }
            lines.append(name + ";" + cells.joined(separator: ";"))
        }
        lines.append("")

        lines.append("Win rate by board size")
        lines.append("Engine;" + configuration.sizes.map { "\($0)x\($0)" }.joined(separator: ";"))
        for (index, name) in participants.enumerated() {
            let cells = configuration.sizes.map { size -> String in
                let r = record(of: index, atSize: size)
                return String(format: "%.3f [%.3f, %.3f] n=%d", r.rate, r.interval.low, r.interval.high, r.games)
            }
            lines.append(name + ";" + cells.joined(separator: ";"))
        }
        lines.append("")

        for side in Player.allCases {
            lines.append("Win rate by board size, playing \(side == .blue ? "Down (first)" : "Across (second)")")
            lines.append("Engine;" + configuration.sizes.map { "\($0)x\($0)" }.joined(separator: ";"))
            for (index, name) in participants.enumerated() {
                let cells = configuration.sizes.map { size -> String in
                    let r = record(of: index, atSize: size, as: side)
                    return String(format: "%.3f [%.3f, %.3f] n=%d", r.rate, r.interval.low, r.interval.high, r.games)
                }
                lines.append(name + ";" + cells.joined(separator: ";"))
            }
            lines.append("")
        }

        lines.append("First-player advantage (first player wins, all pairings)")
        lines.append("Board size;First-player wins;Games;Rate;CI low;CI high")
        for size in configuration.sizes {
            let r = firstPlayerRecord(atSize: size)
            lines.append(
                [
                    "\(size)x\(size)", "\(r.wins)", "\(r.games)",
                    String(format: "%.3f", r.rate),
                    String(format: "%.3f", r.interval.low),
                    String(format: "%.3f", r.interval.high)
                ].joined(separator: ";")
            )
        }
        return lines.joined(separator: "\n")
    }
}
