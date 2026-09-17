import BridgyEngine
import Foundation

/// Saves the game in progress so it survives quitting.
///
/// The original serialised its whole object graph into a file in the system temp
/// directory, derived by creating a throwaway temp file and slicing the path at
/// the last `/`. This writes JSON to Application Support instead, which is where
/// it belongs and which survives a reboot.
struct GameStore: Sendable {

    struct Snapshot: Codable, Sendable {
        var configuration: GameConfiguration
        var state: GameState
    }

    private let url: URL

    init(filename: String = "current-game.json") {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        let directory = base.appendingPathComponent("Bridgy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(filename)
    }

    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
