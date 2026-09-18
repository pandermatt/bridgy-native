/// A way of turning the board over that changes nothing about the game.
///
/// Only four. Each must keep both players' goals where they are, and a quarter
/// turn does not: it swaps top-to-bottom for left-to-right. That swap is what
/// the encoding's transpose is for — it puts whoever is to move in Down's seat —
/// so the quarter turns are already accounted for.
public enum Symmetry: Int, Sendable, CaseIterable {
    case identity
    case mirrorLeftRight
    case mirrorTopBottom
    case halfTurn

    var flipsX: Bool { self == .mirrorLeftRight || self == .halfTurn }
    var flipsY: Bool { self == .mirrorTopBottom || self == .halfTurn }
}

/// What the network sees: the board's lattice as a stack of feature planes,
/// always from the side of the player to move, always as if that player were
/// Down.
///
/// The lattice is the one `Board` already draws on, `(2n+1)²` points where
/// Down's dots, Across's dots and the cells interleave. Across is shown
/// transposed — x and y swapped — which maps Across's dots exactly onto Down's,
/// each cell onto a cell of the same family, and left-to-right onto
/// top-to-bottom. So one network learns one game, and plays both colours.
///
/// Planes, in order, each `side × side`, stored position-major (NHWC):
/// 0. bridges of the player to move
/// 1. bridges of the opponent
/// 2. empty cells
/// 3. dots of the player to move
/// 4. dots of the opponent
/// 5. ones, marking the board, so the network can tell an edge from padding
public enum BoardEncoding {
    public static let planes = 6

    /// Points along one side of the lattice.
    public static func side(for board: Board) -> Int { 2 * board.size + 1 }

    /// Where a lattice point of the real board appears to the network.
    public static func frame(
        _ point: (x: Int, y: Int),
        board: Board,
        mover: Player,
        symmetry: Symmetry
    ) -> (x: Int, y: Int) {
        var (x, y) = mover == .blue ? (point.x, point.y) : (point.y, point.x)
        let last = 2 * board.size
        if symmetry.flipsX { x = last - x }
        if symmetry.flipsY { y = last - y }
        return (x, y)
    }

    /// For each cell of the board, its position in the network's flattened
    /// lattice. Policy logits are read, and policy targets written, through this.
    public static func cellMap(board: Board, mover: Player, symmetry: Symmetry) -> [Int] {
        let side = side(for: board)
        return (0..<board.cellCount).map { cell in
            let p = frame(board.center(of: board.move(at: cell)), board: board, mover: mover, symmetry: symmetry)
            return p.y * side + p.x
        }
    }

    /// The planes for `state`, from the side of the player to move.
    public static func encode(_ state: GameState, symmetry: Symmetry = .identity) -> [Float] {
        let side = side(for: state.board)
        var buffer = [Float](repeating: 0, count: side * side * planes)
        buffer.withUnsafeMutableBufferPointer { encode(state, symmetry: symmetry, into: $0.baseAddress!) }
        return buffer
    }

    /// Writes the planes into `buffer`, which must hold `side² × planes` zeros.
    public static func encode(_ state: GameState, symmetry: Symmetry, into buffer: UnsafeMutablePointer<Float>) {
        let board = state.board
        let n = board.size
        let side = side(for: board)
        let mover = state.current

        func set(_ point: (x: Int, y: Int), _ plane: Int) {
            let p = frame(point, board: board, mover: mover, symmetry: symmetry)
            buffer[(p.y * side + p.x) * planes + plane] = 1
        }

        for index in 0..<(side * side) { buffer[index * planes + 5] = 1 }

        let blueDotPlane = mover == .blue ? 3 : 4
        for row in 0...n {
            for col in 0..<n { set(board.blueDotPosition(row: row, col: col), blueDotPlane) }
        }
        for row in 0..<n {
            for col in 0...n { set(board.redDotPosition(row: row, col: col), 7 - blueDotPlane) }
        }

        for cell in 0..<board.cellCount {
            let plane: Int
            switch state.cells[cell] {
            case nil: plane = 2
            case mover?: plane = 0
            default: plane = 1
            }
            set(board.center(of: board.move(at: cell)), plane)
        }
    }
}
