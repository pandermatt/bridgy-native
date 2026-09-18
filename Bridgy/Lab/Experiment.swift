import BridgyEngine
import CryptoKit
import Foundation
import Observation

/// A question put to the engines, how it is being answered, and every game
/// played to answer it.
struct Experiment: Codable, Identifiable, Hashable, Sendable {

    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Everyone against everyone, both colours, each size.
        case roundRobin
        /// Each engine against itself: the value of moving first, per engine.
        case mirror
        /// One precise claim, tested until the evidence settles it.
        case hypothesis

        var id: String { rawValue }

        var title: String {
            switch self {
            case .roundRobin: "Round Robin"
            case .mirror: "Mirror Matches"
            case .hypothesis: "Hypothesis Test"
            }
        }

        var symbol: String {
            switch self {
            case .roundRobin: "person.3"
            case .mirror: "arrow.left.and.right.righttriangle.left.righttriangle.right"
            case .hypothesis: "checkmark.seal"
            }
        }

        var summary: String {
            switch self {
            case .roundRobin: "Every engine plays every other in both colours at each size. Ratings, head-to-head and first-player advantage."
            case .mirror: "Each engine plays itself, so strength cancels out and only the value of moving first is left."
            case .hypothesis: "Test one claim — say, “A beats B playing Across on 6×6” — and stop as soon as the evidence decides."
            }
        }
    }

    enum Status: String, Codable, Sendable {
        case draft, running, finished, stopped
    }

    /// Who plays: a built-in level or a trained agent, pinned to its exact network.
    struct Entrant: Codable, Hashable, Sendable, Identifiable {
        var name: String
        var level: Difficulty?
        var agentID: UUID?
        /// First 12 hex digits of the SHA-256 of the agent's weights, so a report
        /// says exactly which network played even if the agent is trained on.
        var weightsHash: String?

        var id: String { agentID?.uuidString ?? level?.rawValue ?? name }
    }

    /// "Does `subject` win more than `p0` of its games against `opponent`?"
    struct Hypothesis: Codable, Hashable, Sendable {
        var subject: Int
        var opponent: Int
        var size: Int
        /// Pin the subject to one colour, or alternate.
        var subjectPlays: Player?
        /// The rate that counts as "no, it doesn't" (H0) and "yes, it does" (H1).
        var p0: Double = 0.5
        var p1: Double = 0.6
        var alpha: Double = 0.05
        var beta: Double = 0.05
        /// Stop here even if undecided.
        var maxGames: Int = 2_000
    }

    let id: UUID
    var name: String
    var kind: Kind
    var created: Date
    var status: Status = .draft
    var entrants: [Entrant]
    var sizes: [Int]
    /// Games per colour per pairing per size (round robin), or per engine per
    /// size (mirror).
    var gamesPerUnit: Int
    var hypothesis: Hypothesis?
    var seed: UInt64
    var appVersion: String
    var gamesPlayed = 0
    /// The last write-up, kept so it need not be regenerated.
    var findings: Findings?

    var scheduledGames: Int {
        switch kind {
        case .roundRobin:
            TournamentConfiguration(minimumSize: sizes.min() ?? 4, maximumSize: sizes.max() ?? 4, gamesPerColour: gamesPerUnit)
                .totalGames(participants: entrants.count)
        case .mirror:
            sizes.count * entrants.count * gamesPerUnit
        case .hypothesis:
            hypothesis?.maxGames ?? 0
        }
    }

    /// The question, in words, for the list, the report and Siri.
    var question: String {
        switch kind {
        case .roundRobin:
            return "How do \(entrants.map(\.name).formatted()) rank on \(sizeText) boards?"
        case .mirror:
            return "How much is moving first worth to each engine on \(sizeText) boards?"
        case .hypothesis:
            guard let h = hypothesis, entrants.indices.contains(h.subject), entrants.indices.contains(h.opponent) else {
                return "Hypothesis"
            }
            let colour = h.subjectPlays.map { " playing \($0.displayName)" } ?? ""
            return "Does \(entrants[h.subject].name)\(colour) beat \(entrants[h.opponent].name) more than \(Int(h.p0 * 100))% of the time on \(h.size)×\(h.size)?"
        }
    }

    var sizeText: String {
        guard let low = sizes.min(), let high = sizes.max() else { return "" }
        return low == high ? "\(low)×\(low)" : "\(low)×\(low) to \(high)×\(high)"
    }

    static var currentAppVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static func hash(of weights: NetworkWeights) -> String {
        SHA256.hash(data: weights.data()).map { String(format: "%02x", $0) }.joined().prefix(12).description
    }
}

/// One finished game, enough to replay it exactly.
struct GameRecord: Codable, Hashable, Sendable, Identifiable {
    var id: Int { index }
    let index: Int
    let size: Int
    /// Entrant indices.
    let down: Int
    let across: Int
    let winner: Player
    let moves: [UInt16]
    let seed: UInt64

    init(_ outcome: Tournament.Outcome) {
        index = outcome.gameIndex
        size = outcome.size
        down = outcome.blue
        across = outcome.red
        winner = outcome.winner
        moves = outcome.moves
        seed = outcome.seed
    }

    /// A game played in Play, where "Down" and "Across" are indices 0 and 1
    /// into the history entry's own names.
    init(state: GameState, seed: UInt64 = 0) {
        index = 0
        size = state.board.size
        down = 0
        across = 1
        winner = state.winner ?? .blue
        moves = state.moves.map { UInt16(state.board.index(of: $0)) }
        self.seed = seed
    }

    var outcome: Tournament.Outcome {
        Tournament.Outcome(gameIndex: index, size: size, blue: down, red: across, winner: winner, moves: moves, seed: seed)
    }

    var length: Int { moves.count }

    /// The position after `count` moves.
    func position(after count: Int) -> GameState {
        var state = GameState(size: size)
        for cell in moves.prefix(count) { state.apply(state.board.move(at: Int(cell))) }
        return state
    }
}

/// Experiments on disk: `Application Support/Bridgy/Experiments/<id>/`, with
/// the description in `experiment.json` and the games in `games.json`.
@MainActor
@Observable
final class ExperimentLibrary {
    private(set) var experiments: [Experiment] = []
    private let directory: URL
    @ObservationIgnored private var gameCache: [UUID: [GameRecord]] = [:]

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL.temporaryDirectory
        directory = base.appendingPathComponent("Bridgy/Experiments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    private func folder(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        experiments = folders
            .compactMap { try? Data(contentsOf: $0.appendingPathComponent("experiment.json")) }
            .compactMap { try? JSONDecoder().decode(Experiment.self, from: $0) }
            // One interrupted by quitting is not still running.
            .map { var e = $0; if e.status == .running { e.status = .stopped }; return e }
            .sorted { $0.created > $1.created }
    }

    func experiment(_ id: UUID) -> Experiment? { experiments.first { $0.id == id } }

    func save(_ experiment: Experiment, games: [GameRecord]? = nil) {
        let folder = folder(experiment.id)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(experiment) {
            try? data.write(to: folder.appendingPathComponent("experiment.json"), options: .atomic)
        }
        if let games {
            gameCache[experiment.id] = games
            if let data = try? JSONEncoder().encode(games) {
                try? data.write(to: folder.appendingPathComponent("games.json"), options: .atomic)
            }
        }
        if let index = experiments.firstIndex(where: { $0.id == experiment.id }) {
            experiments[index] = experiment
        } else {
            experiments.insert(experiment, at: 0)
        }
    }

    func games(for id: UUID) -> [GameRecord] {
        if let cached = gameCache[id] { return cached }
        let url = folder(id).appendingPathComponent("games.json")
        let games = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([GameRecord].self, from: $0) } ?? []
        gameCache[id] = games
        return games
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(id))
        experiments.removeAll { $0.id == id }
        gameCache[id] = nil
    }

    func rename(_ id: UUID, to name: String) {
        guard var experiment = experiment(id) else { return }
        experiment.name = name
        save(experiment)
    }
}
