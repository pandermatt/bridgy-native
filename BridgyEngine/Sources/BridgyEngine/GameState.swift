/// A complete Bridg-It position: who owns which cell, whose turn it is, and
/// whether anyone has won.
///
/// Connectivity is tracked incrementally with one `DisjointSet` per player over
/// that player's dots plus two virtual terminals. Blue has won exactly when its
/// `top` and `bottom` terminals share a set.
public struct GameState: Sendable, Hashable, Codable {

    public let board: Board
    /// Owner of each cell, indexed by `board.index(of:)`. `nil` means empty.
    public private(set) var cells: [Player?]
    public private(set) var moves: [Move]
    public private(set) var current: Player
    public private(set) var winner: Player?

    private var blue: DisjointSet
    private var red: DisjointSet

    private var blueTop: Int { board.blueDotCount }
    private var blueBottom: Int { board.blueDotCount + 1 }
    private var redLeft: Int { board.redDotCount }
    private var redRight: Int { board.redDotCount + 1 }

    public init(size: Int) {
        self.init(board: Board(size: size))
    }

    public init(board: Board) {
        self.board = board
        self.cells = [Player?](repeating: nil, count: board.cellCount)
        self.moves = []
        self.current = .first
        self.winner = nil
        self.blue = DisjointSet(count: board.blueDotCount + 2)
        self.red = DisjointSet(count: board.redDotCount + 2)
        seedTerminals()
    }

    /// Ties each player's goal edges to its two virtual terminals, so that a
    /// win is a single `connected` query rather than a search over border dots.
    private mutating func seedTerminals() {
        let n = board.size
        for col in 0..<n {
            blue.union(board.blueDot(row: 0, col: col), blueTop)
            blue.union(board.blueDot(row: n, col: col), blueBottom)
        }
        for row in 0..<n {
            red.union(board.redDot(row: row, col: 0), redLeft)
            red.union(board.redDot(row: row, col: n), redRight)
        }
    }

    // MARK: - Queries

    public var isOver: Bool { winner != nil }

    public var moveCount: Int { moves.count }

    public func owner(of move: Move) -> Player? { cells[board.index(of: move)] }

    public func isLegal(_ move: Move) -> Bool {
        winner == nil && board.contains(move) && cells[board.index(of: move)] == nil
    }

    public var legalMoves: [Move] {
        guard winner == nil else { return [] }
        var result: [Move] = []
        result.reserveCapacity(cells.count - moves.count)
        for index in cells.indices where cells[index] == nil {
            result.append(board.move(at: index))
        }
        return result
    }

    public var legalMoveIndices: [Int] {
        guard winner == nil else { return [] }
        return cells.indices.filter { cells[$0] == nil }
    }

    /// Whether `player` taking `move` would win outright.
    public func wouldWin(_ move: Move, for player: Player) -> Bool {
        guard isLegal(move) else { return false }
        var sets = player == .blue ? blue : red
        let (a, b) = board.endpoints(move, for: player)
        sets.union(a, b)
        let terminals = player == .blue ? (blueTop, blueBottom) : (redLeft, redRight)
        return sets.connected(terminals.0, terminals.1)
    }

    // MARK: - Mutation

    /// Plays `move` for whoever is to move.
    @discardableResult
    public mutating func apply(_ move: Move) -> Bool {
        guard isLegal(move) else { return false }
        let player = current
        cells[board.index(of: move)] = player

        let (a, b) = board.endpoints(move, for: player)
        if player == .blue {
            blue.union(a, b)
            if blue.connected(blueTop, blueBottom) { winner = .blue }
        } else {
            red.union(a, b)
            if red.connected(redLeft, redRight) { winner = .red }
        }

        moves.append(move)
        if winner == nil { current = player.opponent }
        return true
    }

    public var canUndo: Bool { !moves.isEmpty }

    /// Takes back the last move. Unlike the original's `revertLastMove`, which
    /// was disabled behind a `canRevertLastMove()` that always returned false,
    /// this actually works: the connectivity structures are rebuilt by replay.
    @discardableResult
    public mutating func undo() -> Move? {
        guard let last = moves.last else { return nil }
        replay(Array(moves.dropLast()))
        return last
    }

    /// Takes back moves until it is `player`'s turn again, so a human undoing
    /// against a computer opponent does not simply hand the turn back to it.
    @discardableResult
    public mutating func undo(untilTurnOf player: Player) -> Int {
        var removed = 0
        while canUndo {
            undo()
            removed += 1
            if current == player && !isOver { break }
        }
        return removed
    }

    private mutating func replay(_ history: [Move]) {
        cells = [Player?](repeating: nil, count: board.cellCount)
        moves = []
        current = .first
        winner = nil
        blue = DisjointSet(count: board.blueDotCount + 2)
        red = DisjointSet(count: board.redDotCount + 2)
        seedTerminals()
        for move in history { apply(move) }
    }
}
