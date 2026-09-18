import BridgyEngine
import Foundation

typealias Record = TournamentAnalysis.Record

/// Everything the Lab shows about an experiment, computed from its games.
///
/// Cheap parts are computed on every refresh; the bootstrap is left to
/// `RatingAnalysis.run`, called separately and off the main thread.
struct ExperimentAnalysis: Sendable {
    let experiment: Experiment
    let games: [GameRecord]

    init(experiment: Experiment, games: [GameRecord]) {
        self.experiment = experiment
        self.games = games
    }

    var names: [String] { experiment.entrants.map(\.name) }

    // MARK: - Round robin

    /// The running tallies and Elo history, as the tournament charts want them.
    var tournament: TournamentAnalysis {
        var analysis = TournamentAnalysis(
            participants: names,
            configuration: TournamentConfiguration(
                minimumSize: experiment.sizes.min() ?? 4,
                maximumSize: experiment.sizes.max() ?? 4,
                gamesPerColour: experiment.gamesPerUnit
            )
        )
        for game in games where game.down != game.across { analysis.record(game.outcome) }
        analysis.finish()
        return analysis
    }

    var bradleyTerryGames: [BradleyTerry.Game] {
        games.filter { $0.down != $0.across }
            .map { BradleyTerry.Game(down: $0.down, across: $0.across, downWon: $0.winner == .blue) }
    }

    // MARK: - First player

    struct SizeRecord: Identifiable, Hashable, Sendable {
        var id: String { "\(series)-\(size)" }
        let series: String
        let size: Int
        let record: Record
    }

    /// Down's record at each size, over every game.
    var firstPlayerBySize: [SizeRecord] {
        Dictionary(grouping: games, by: \.size).keys.sorted().map { size in
            let atSize = games.filter { $0.size == size }
            return SizeRecord(series: "All", size: size,
                              record: Record(wins: atSize.filter { $0.winner == .blue }.count, games: atSize.count))
        }
    }

    /// Down's record at each size for each engine playing itself.
    var mirrorBySize: [SizeRecord] {
        var result: [SizeRecord] = []
        for (index, name) in names.enumerated() {
            let own = games.filter { $0.down == index && $0.across == index }
            for size in Set(own.map(\.size)).sorted() {
                let atSize = own.filter { $0.size == size }
                result.append(SizeRecord(series: name, size: size,
                                         record: Record(wins: atSize.filter { $0.winner == .blue }.count, games: atSize.count)))
            }
        }
        return result
    }

    // MARK: - Hypothesis

    struct EvidencePoint: Identifiable, Hashable, Sendable {
        var id: Int { games }
        let games: Int
        let logLikelihoodRatio: Double
    }

    /// The test replayed game by game, for the evidence chart.
    var evidence: (test: SequentialTest, path: [EvidencePoint])? {
        guard let h = experiment.hypothesis else { return nil }
        var test = SequentialTest(p0: h.p0, p1: h.p1, alpha: h.alpha, beta: h.beta)
        var path = [EvidencePoint(games: 0, logLikelihoodRatio: 0)]
        for game in games.sorted(by: { $0.index < $1.index }) {
            let subjectWon = (game.winner == .blue ? game.down : game.across) == h.subject
            test.record(win: subjectWon)
            path.append(EvidencePoint(games: test.games, logLikelihoodRatio: test.logLikelihoodRatio))
            if test.decision != .undecided { break }
        }
        return (test, path)
    }

    // MARK: - Significance

    struct Pairing: Identifiable, Hashable, Sendable {
        var id: String { "\(row)-\(column)" }
        let row: Int
        let column: Int
        let record: Record
        let pValue: Double
        var adjusted: Double = 1
        var isSignificant: Bool { adjusted < 0.05 }
    }

    /// Every pairing's record, tested against an even split, Holm-adjusted
    /// across all pairings at once.
    var pairings: [Pairing] {
        var result: [Pairing] = []
        for row in names.indices {
            for column in names.indices where column > row {
                let between = games.filter {
                    ($0.down == row && $0.across == column) || ($0.down == column && $0.across == row)
                }
                guard !between.isEmpty else { continue }
                let wins = between.filter { ($0.winner == .blue ? $0.down : $0.across) == row }.count
                result.append(Pairing(
                    row: row, column: column,
                    record: Record(wins: wins, games: between.count),
                    pValue: Significance.binomialPValue(wins: wins, games: between.count)
                ))
            }
        }
        let adjusted = Significance.holm(result.map(\.pValue))
        for index in result.indices { result[index].adjusted = adjusted[index] }
        return result
    }
}
