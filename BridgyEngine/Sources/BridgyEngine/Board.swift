/// Geometry of a Bridg-It board.
///
/// The board is expressed as a set of *contested cells*. Every legal move in
/// Bridg-It occupies one cell, and each cell can be claimed by either player —
/// whoever reaches it first. That is what makes building and blocking the same
/// act, and it is why a single `cells` array is enough to describe a position.
///
/// Two families of cell exist, for a board of size `n`:
///
/// - `.v`, an `n x n` grid. Blue plays the vertical edge `B(r,c)-B(r+1,c)`;
///   red plays the horizontal edge `R(r,c)-R(r,c+1)`.
/// - `.h`, an `(n-1) x (n-1)` grid. Blue plays the horizontal edge
///   `B(r+1,c)-B(r+1,c+1)`; red plays the vertical edge `R(r,c+1)-R(r+1,c+1)`.
///
/// Blue's dots sit at `(2c+1, 2r)` and red's at `(2c, 2r+1)` in a unit lattice
/// spanning `0...2n` on both axes, which interleaves the two and puts each
/// family's cells at the midpoints listed in `center(of:)`.
public struct Board: Sendable, Hashable, Codable {

    /// Smallest playable board.
    public static let minimumSize = 2

    /// Largest playable board, matching the original Java implementation.
    public static let maximumSize = 35

    /// Number of cells along one edge of the `.v` family.
    public let size: Int

    public init(size: Int) {
        precondition(
            (Board.minimumSize...Board.maximumSize).contains(size),
            "Board size must be in \(Board.minimumSize)...\(Board.maximumSize)"
        )
        self.size = size
    }

    // MARK: - Cells

    public var vCount: Int { size * size }
    public var hCount: Int { (size - 1) * (size - 1) }

    /// Total number of playable cells. Always odd, so blue — who moves first —
    /// gets one more move than red on a completely filled board.
    public var cellCount: Int { vCount + hCount }

    public func index(of move: Move) -> Int {
        switch move.kind {
        case .v: return move.row * size + move.col
        case .h: return vCount + move.row * (size - 1) + move.col
        }
    }

    public func move(at index: Int) -> Move {
        if index < vCount {
            return Move(kind: .v, row: index / size, col: index % size)
        }
        let offset = index - vCount
        let span = size - 1
        return Move(kind: .h, row: offset / span, col: offset % span)
    }

    public func contains(_ move: Move) -> Bool {
        switch move.kind {
        case .v: return (0..<size).contains(move.row) && (0..<size).contains(move.col)
        case .h: return (0..<(size - 1)).contains(move.row) && (0..<(size - 1)).contains(move.col)
        }
    }

    public var allMoves: [Move] { (0..<cellCount).map(move(at:)) }

    // MARK: - Dot graphs

    /// Blue owns `(n+1) x n` dots: `n+1` rows of `n`.
    public var blueDotCount: Int { (size + 1) * size }

    /// Red owns `n x (n+1)` dots: `n` rows of `n+1`.
    public var redDotCount: Int { size * (size + 1) }

    public func blueDot(row: Int, col: Int) -> Int { row * size + col }
    public func redDot(row: Int, col: Int) -> Int { row * (size + 1) + col }

    /// The two blue dots a move would join, were blue to play it.
    public func blueEndpoints(_ move: Move) -> (Int, Int) {
        switch move.kind {
        case .v:
            return (blueDot(row: move.row, col: move.col),
                    blueDot(row: move.row + 1, col: move.col))
        case .h:
            return (blueDot(row: move.row + 1, col: move.col),
                    blueDot(row: move.row + 1, col: move.col + 1))
        }
    }

    /// The two red dots a move would join, were red to play it.
    public func redEndpoints(_ move: Move) -> (Int, Int) {
        switch move.kind {
        case .v:
            return (redDot(row: move.row, col: move.col),
                    redDot(row: move.row, col: move.col + 1))
        case .h:
            return (redDot(row: move.row, col: move.col + 1),
                    redDot(row: move.row + 1, col: move.col + 1))
        }
    }

    public func endpoints(_ move: Move, for player: Player) -> (Int, Int) {
        player == .blue ? blueEndpoints(move) : redEndpoints(move)
    }

    public func dotCount(for player: Player) -> Int {
        player == .blue ? blueDotCount : redDotCount
    }

    // MARK: - Layout

    /// Extent of the drawing lattice on both axes: coordinates run `0...span`.
    public var span: Int { 2 * size }

    /// Lattice position of a blue dot.
    public func blueDotPosition(row: Int, col: Int) -> (x: Int, y: Int) {
        (x: 2 * col + 1, y: 2 * row)
    }

    /// Lattice position of a red dot.
    public func redDotPosition(row: Int, col: Int) -> (x: Int, y: Int) {
        (x: 2 * col, y: 2 * row + 1)
    }

    /// Lattice midpoint of a cell — where the two players' candidate edges cross.
    public func center(of move: Move) -> (x: Int, y: Int) {
        switch move.kind {
        case .v: return (x: 2 * move.col + 1, y: 2 * move.row + 1)
        case .h: return (x: 2 * move.col + 2, y: 2 * move.row + 2)
        }
    }
}
