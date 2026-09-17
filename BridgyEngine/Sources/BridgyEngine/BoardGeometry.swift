import CoreGraphics

/// Maps between the board's integer lattice and points on screen.
///
/// Blue's dots sit at `(2c+1, 2r)` and red's at `(2c, 2r+1)`, so the two grids
/// interleave and every cell centre falls exactly between the four dots around
/// it. Everything on screen derives from that one lattice.
public struct BoardGeometry {

    /// A dot belonging to one player.
    public struct Dot: Hashable, Sendable {
        public let player: Player
        public let row: Int
        public let col: Int

        public init(player: Player, row: Int, col: Int) {
            self.player = player
            self.row = row
            self.col = col
        }
    }

    public let board: Board
    public let rect: CGRect

    public init(board: Board, rect: CGRect) {
        self.board = board
        self.rect = rect
    }

    /// Breathing room around the outermost dots, in lattice units.
    private static let padding: CGFloat = 0.8

    public var scale: CGFloat {
        let units = CGFloat(board.span) + 2 * Self.padding
        return min(rect.width, rect.height) / units
    }

    /// Where lattice `(0, 0)` lands, with the board centred in `rect`.
    public var origin: CGPoint {
        let side = CGFloat(board.span) * scale
        return CGPoint(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2
        )
    }

    public var dotRadius: CGFloat { max(1.5, scale * 0.22) }
    public var lineWidth: CGFloat { max(2, scale * 0.34) }
    public var boldLineWidth: CGFloat { max(3, scale * 0.52) }

    public func point(latticeX x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    public func lattice(of point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }

    // MARK: - Dots

    public func point(of dot: Dot) -> CGPoint {
        let position = dot.player == .blue
            ? board.blueDotPosition(row: dot.row, col: dot.col)
            : board.redDotPosition(row: dot.row, col: dot.col)
        return point(latticeX: CGFloat(position.x), y: CGFloat(position.y))
    }

    public func dots(for player: Player) -> [Dot] {
        let n = board.size
        let rows = player == .blue ? 0...n : 0...(n - 1)
        let cols = player == .blue ? 0...(n - 1) : 0...n
        return rows.flatMap { row in cols.map { Dot(player: player, row: row, col: $0) } }
    }

    private func dot(ofID id: Int, player: Player) -> Dot {
        let stride = player == .blue ? board.size : board.size + 1
        return Dot(player: player, row: id / stride, col: id % stride)
    }

    /// The two screen points a move's edge runs between.
    public func endpoints(of move: Move, for player: Player) -> (CGPoint, CGPoint) {
        let (a, b) = board.endpoints(move, for: player)
        return (point(of: dot(ofID: a, player: player)), point(of: dot(ofID: b, player: player)))
    }

    public func center(of move: Move) -> CGPoint {
        let position = board.center(of: move)
        return point(latticeX: CGFloat(position.x), y: CGFloat(position.y))
    }

    // MARK: - Hit testing

    /// The closest cell to `point` that passes `isAllowed`.
    ///
    /// Both families are searched, so tapping in the gap where you want a bridge
    /// finds it whichever grid it belongs to. Taken cells are skipped rather than
    /// swallowing the tap.
    ///
    /// The default radius is just over `√2`, which is the distance from one cell
    /// centre to its nearest neighbour in the other family. Anything less and a
    /// tap landing dead centre on an occupied cell finds nothing at all, while a
    /// tap a hair off-centre falls through to a neighbour — the same gesture
    /// giving two different answers.
    public func nearestCell(to point: CGPoint, within radius: CGFloat = 1.5, isAllowed: (Move) -> Bool) -> Move? {
        let target = lattice(of: point)
        var best: (move: Move, distance: CGFloat)?

        func consider(_ move: Move) {
            guard board.contains(move), isAllowed(move) else { return }
            let position = board.center(of: move)
            let dx = target.x - CGFloat(position.x)
            let dy = target.y - CGFloat(position.y)
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance <= radius else { return }
            if best == nil || distance < best!.distance { best = (move, distance) }
        }

        // .v centres are at odd lattice coordinates, .h centres at even ones.
        let vCol = Int(((target.x - 1) / 2).rounded())
        let vRow = Int(((target.y - 1) / 2).rounded())
        let hCol = Int(((target.x - 2) / 2).rounded())
        let hRow = Int(((target.y - 2) / 2).rounded())
        for rowOffset in -1...1 {
            for colOffset in -1...1 {
                consider(Move(kind: .v, row: vRow + rowOffset, col: vCol + colOffset))
                consider(Move(kind: .h, row: hRow + rowOffset, col: hCol + colOffset))
            }
        }
        return best?.move
    }

    /// The closest dot belonging to `player`.
    public func nearestDot(to point: CGPoint, for player: Player, within radius: CGFloat = 1.0) -> Dot? {
        let target = lattice(of: point)
        let n = board.size
        let row: Int
        let col: Int
        if player == .blue {
            col = Int(((target.x - 1) / 2).rounded())
            row = Int((target.y / 2).rounded())
        } else {
            col = Int((target.x / 2).rounded())
            row = Int(((target.y - 1) / 2).rounded())
        }
        let maxRow = player == .blue ? n : n - 1
        let maxCol = player == .blue ? n - 1 : n
        guard (0...maxRow).contains(row), (0...maxCol).contains(col) else { return nil }
        let candidate = Dot(player: player, row: row, col: col)
        let position = self.point(of: candidate)
        let dx = (position.x - point.x) / scale
        let dy = (position.y - point.y) / scale
        guard (dx * dx + dy * dy).squareRoot() <= radius else { return nil }
        return candidate
    }

    /// The cell joining two adjacent dots of the same player, if they are adjacent.
    public func cell(between first: Dot, and second: Dot) -> Move? {
        guard first.player == second.player, first != second else { return nil }
        let n = board.size
        let rowGap = abs(first.row - second.row)
        let colGap = abs(first.col - second.col)
        let lowRow = min(first.row, second.row)
        let lowCol = min(first.col, second.col)

        switch first.player {
        case .blue:
            if colGap == 0, rowGap == 1 {
                return Move(kind: .v, row: lowRow, col: first.col)
            }
            if rowGap == 0, colGap == 1, (1...(n - 1)).contains(first.row) {
                return Move(kind: .h, row: first.row - 1, col: lowCol)
            }
        case .red:
            if rowGap == 0, colGap == 1 {
                return Move(kind: .v, row: first.row, col: lowCol)
            }
            if colGap == 0, rowGap == 1, (1...(n - 1)).contains(first.col) {
                return Move(kind: .h, row: lowRow, col: first.col - 1)
            }
        }
        return nil
    }
}
