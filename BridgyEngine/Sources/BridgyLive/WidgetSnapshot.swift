import Foundation

/// What the home-screen widget shows: the game in progress, as the app last
/// saw it. Written by the app into the shared App Group, read by the widget.
public struct WidgetSnapshot: Codable, Sendable, Hashable {
    public var title: String
    public var detail: String
    public var moves: Int
    public var isYourTurn: Bool
    public var isOver: Bool
    public var updated: Date

    public init(title: String, detail: String, moves: Int, isYourTurn: Bool, isOver: Bool, updated: Date = .now) {
        self.title = title
        self.detail = detail
        self.moves = moves
        self.isYourTurn = isYourTurn
        self.isOver = isOver
        self.updated = updated
    }

    public static let appGroup = "group.ch.pandermatt.bridgy"

    public static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    public static var dataURL: URL? { directory?.appendingPathComponent("widget.json") }
    public static var boardURL: URL? { directory?.appendingPathComponent("widget-board.png") }

    public static func load() -> WidgetSnapshot? {
        guard let url = dataURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func save() {
        guard let url = Self.dataURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func clear() {
        if let url = dataURL { try? FileManager.default.removeItem(at: url) }
        if let url = boardURL { try? FileManager.default.removeItem(at: url) }
    }

    /// Links the widget opens.
    public static let continueURL = URL(string: "bridgy://continue")!
    public static let puzzleURL = URL(string: "bridgy://puzzle")!
    public static let newGameURL = URL(string: "bridgy://new")!
}
