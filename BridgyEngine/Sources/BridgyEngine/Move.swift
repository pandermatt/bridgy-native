/// One of the two players.
///
/// Blue is player 1 in the original: it moves first and needs a top-to-bottom
/// chain. Red needs left-to-right.
///
/// The case names are historical and geometric — they are what the original
/// called the two sides, and they pin down which dot lattice each player owns.
/// They are deliberately *not* what the app shows: a theme can make the second
/// player orange, so the UI names them by direction instead, Down and Across.
/// See `Player.displayName`.
public enum Player: Int, Sendable, Hashable, Codable, CaseIterable {
    case blue = 0
    case red = 1

    public var opponent: Player { self == .blue ? .red : .blue }

    /// The player who opens the game.
    public static var first: Player { .blue }
}

/// Which family of contested cell a move occupies.
public enum CellKind: Int, Sendable, Hashable, Codable, CaseIterable {
    /// The `n x n` family. Vertical for blue, horizontal for red.
    case v = 0
    /// The `(n-1) x (n-1)` family. Horizontal for blue, vertical for red.
    case h = 1
}

/// A placement on a contested cell. Which edge it draws depends on who plays it.
public struct Move: Sendable, Hashable, Codable {
    public let kind: CellKind
    public let row: Int
    public let col: Int

    public init(kind: CellKind, row: Int, col: Int) {
        self.kind = kind
        self.row = row
        self.col = col
    }

    /// Whether the edge runs vertically on screen when played by `player`.
    public func isVertical(for player: Player) -> Bool {
        switch kind {
        case .v: return player == .blue
        case .h: return player == .red
        }
    }
}

extension Move: CustomStringConvertible {
    public var description: String {
        "\(kind == .v ? "v" : "h")(\(row),\(col))"
    }
}
