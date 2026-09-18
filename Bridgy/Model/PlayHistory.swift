import BridgyEngine
import Foundation
import Observation

/// One finished game from Play, kept so it can be replayed and recapped.
struct PlayedGame: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let record: GameRecord
    /// Who played Down and Across, as the replay shows them.
    let names: [String]
    let configuration: GameConfiguration

    var title: String { "\(names[0]) v \(names[1])" }

    var winnerName: String { names[record.winner == .blue ? 0 : 1] }
}

/// The last finished games, newest first, in
/// `Application Support/Bridgy/history.json`.
@MainActor
@Observable
final class PlayHistory {
    private(set) var games: [PlayedGame] = []
    private let url: URL
    private static let limit = 1_000

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL.temporaryDirectory
        let directory = base.appendingPathComponent("Bridgy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("history.json")
        games = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([PlayedGame].self, from: $0) } ?? []
    }

    /// Adds a finished game. The same position recorded twice — a result sheet
    /// shown again — is only kept once.
    @discardableResult
    func record(_ state: GameState, configuration: GameConfiguration) -> PlayedGame? {
        guard state.isOver else { return nil }
        let record = GameRecord(state: state)
        if let existing = games.first(where: { $0.record.moves == record.moves && $0.record.size == record.size }) {
            return existing
        }
        let game = PlayedGame(
            id: UUID(), date: .now, record: record,
            names: [configuration.blue.displayName, configuration.red.displayName],
            configuration: configuration
        )
        games.insert(game, at: 0)
        if games.count > Self.limit { games.removeLast(games.count - Self.limit) }
        if let data = try? JSONEncoder().encode(games) { try? data.write(to: url, options: .atomic) }
        return game
    }

    func delete(_ game: PlayedGame) {
        games.removeAll { $0.id == game.id }
        if let data = try? JSONEncoder().encode(games) { try? data.write(to: url, options: .atomic) }
    }
}
