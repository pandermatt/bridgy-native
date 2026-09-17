import CoreGraphics
import Testing
@testable import BridgyEngine

@Suite("Board layout and hit testing")
struct BoardGeometryTests {

    private func geometry(size: Int, side: CGFloat = 400) -> BoardGeometry {
        BoardGeometry(board: Board(size: size), rect: CGRect(x: 0, y: 0, width: side, height: side))
    }

    @Test("Every cell's centre maps back to itself", arguments: [2, 3, 6, 12])
    func tappingACentreFindsThatCell(size: Int) {
        let geometry = geometry(size: size)
        for move in geometry.board.allMoves {
            let point = geometry.center(of: move)
            let found = geometry.nearestCell(to: point, isAllowed: { _ in true })
            #expect(found == move, "tapping the centre of \(move) found \(String(describing: found))")
        }
    }

    @Test("Every dot maps back to itself", arguments: [2, 3, 6, 12])
    func tappingADotFindsThatDot(size: Int) {
        let geometry = geometry(size: size)
        for player in Player.allCases {
            for dot in geometry.dots(for: player) {
                let point = geometry.point(of: dot)
                #expect(geometry.nearestDot(to: point, for: player) == dot)
            }
        }
    }

    @Test("Taken cells are skipped rather than swallowing the tap")
    func occupiedCellsAreSkipped() {
        let geometry = geometry(size: 6)
        let taken = Move(kind: .v, row: 2, col: 2)
        let point = geometry.center(of: taken)
        let found = geometry.nearestCell(to: point, isAllowed: { $0 != taken })
        #expect(found != nil, "a tap on an occupied cell must still reach a free neighbour")
        #expect(found != taken, "a taken cell must not absorb the tap")
    }

    @Test("A tap just off centre resolves the same way as one dead centre")
    func fallThroughIsConsistent() {
        let geometry = geometry(size: 6)
        let taken = Move(kind: .v, row: 2, col: 2)
        let centre = geometry.center(of: taken)
        let dead = geometry.nearestCell(to: centre, isAllowed: { $0 != taken })
        // Nudging a fraction of a cell in any direction must not change whether
        // the tap lands at all, only which neighbour it picks.
        for (dx, dy) in [(0.1, 0.0), (-0.1, 0.0), (0.0, 0.1), (0.0, -0.1)] {
            let nudged = CGPoint(
                x: centre.x + dx * geometry.scale,
                y: centre.y + dy * geometry.scale
            )
            #expect(geometry.nearestCell(to: nudged, isAllowed: { $0 != taken }) != nil)
        }
        #expect(dead != nil)
    }

    @Test("A drag between two adjacent dots names the cell between them", arguments: [2, 3, 6, 12])
    func adjacentDotsResolveToTheCellBetween(size: Int) {
        let geometry = geometry(size: size)
        for move in geometry.board.allMoves {
            for player in Player.allCases {
                let (a, b) = geometry.board.endpoints(move, for: player)
                let stride = player == .blue ? size : size + 1
                let first = BoardGeometry.Dot(player: player, row: a / stride, col: a % stride)
                let second = BoardGeometry.Dot(player: player, row: b / stride, col: b % stride)
                #expect(geometry.cell(between: first, and: second) == move)
                #expect(geometry.cell(between: second, and: first) == move, "order must not matter")
            }
        }
    }

    @Test("Dots that are not adjacent name no cell")
    func distantDotsResolveToNothing() {
        let geometry = geometry(size: 6)
        let origin = BoardGeometry.Dot(player: .blue, row: 0, col: 0)
        #expect(geometry.cell(between: origin, and: origin) == nil)
        #expect(geometry.cell(between: origin, and: BoardGeometry.Dot(player: .blue, row: 3, col: 3)) == nil)
        #expect(geometry.cell(between: origin, and: BoardGeometry.Dot(player: .red, row: 0, col: 1)) == nil,
                "dots of different colours are never joined")
    }

    @Test("A tap far from the board finds nothing")
    func distantTapsMissEntirely() {
        let geometry = geometry(size: 6)
        #expect(geometry.nearestCell(to: CGPoint(x: -500, y: -500), isAllowed: { _ in true }) == nil)
        #expect(geometry.nearestDot(to: CGPoint(x: -500, y: -500), for: .blue) == nil)
    }

    @Test("The board stays inside its rect at every size", arguments: [2, 5, 12, 35])
    func layoutFitsTheRect(size: Int) {
        let side: CGFloat = 400
        let geometry = geometry(size: size, side: side)
        for player in Player.allCases {
            for dot in geometry.dots(for: player) {
                let point = geometry.point(of: dot)
                #expect(point.x >= 0 && point.x <= side)
                #expect(point.y >= 0 && point.y <= side)
            }
        }
    }
}
