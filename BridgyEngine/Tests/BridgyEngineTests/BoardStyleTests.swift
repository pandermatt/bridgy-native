import CoreGraphics
import Testing
@testable import BridgyEngine

@Suite("Board style geometry")
struct BoardStyleTests {

    private func geometry(size: Int, side: CGFloat = 800) -> BoardGeometry {
        BoardGeometry(board: Board(size: size), rect: CGRect(x: 0, y: 0, width: side, height: side))
    }

    /// The premise the whole thing rests on: blue and red bridges interleave, so
    /// two parallel bridges are never closer than one lattice unit — and never
    /// further apart than that either, when they belong to opposite players.
    @Test("Blue and red bridges interleave on the lattice", arguments: 2...12)
    func bridgesInterleave(size: Int) {
        let board = Board(size: size)

        func bluePoint(_ id: Int) -> (x: Int, y: Int) {
            board.blueDotPosition(row: id / size, col: id % size)
        }
        func redPoint(_ id: Int) -> (x: Int, y: Int) {
            board.redDotPosition(row: id / (size + 1), col: id % (size + 1))
        }

        for move in board.allMoves {
            let (b0, b1) = board.blueEndpoints(move)
            let (bp0, bp1) = (bluePoint(b0), bluePoint(b1))
            if bp0.y == bp1.y {
                #expect(bp0.y.isMultiple(of: 2), "a blue horizontal should sit on an even row")
            } else {
                #expect(!bp0.x.isMultiple(of: 2), "a blue vertical should sit on an odd column")
            }

            let (r0, r1) = board.redEndpoints(move)
            let (rp0, rp1) = (redPoint(r0), redPoint(r1))
            if rp0.y == rp1.y {
                #expect(!rp0.y.isMultiple(of: 2), "a red horizontal should sit on an odd row")
            } else {
                #expect(rp0.x.isMultiple(of: 2), "a red vertical should sit on an even column")
            }
        }
    }

    @Test("Bolder is exactly one lattice unit wide, at every size", arguments: [2, 4, 6, 12, 35])
    func bolderExactlyTouches(size: Int) {
        #expect(BoardStyle.bolder.strokeLatticeWidth == 1)
        let geometry = geometry(size: size)
        let width = geometry.scale * BoardStyle.bolder.strokeLatticeWidth
        #expect(abs(width - geometry.scale) < 1e-9, "Bolder must be exactly one lattice unit")
    }

    @Test("Every other style leaves a gap")
    func othersLeaveAGap() {
        for style in BoardStyle.allCases where style != .bolder {
            #expect(
                style.strokeLatticeWidth < 1,
                "\(style.displayName) is wide enough to collide with its neighbours"
            )
        }
    }

    @Test("Nothing overlaps: no style exceeds a lattice unit")
    func nothingOverlaps() {
        for style in BoardStyle.allCases {
            #expect(style.strokeLatticeWidth <= 1, "\(style.displayName) would overlap a neighbour")
        }
    }

    @Test("fillsItsCell agrees with the width it is derived from")
    func fillsItsCellMatchesWidth() {
        for style in BoardStyle.allCases {
            #expect(style.fillsItsCell == (style.strokeLatticeWidth >= 1))
        }
    }

    /// Styles without dots must not claim to draw only the joined ones.
    @Test("Dot behaviour is consistent with the style's weight")
    func dotsAreConsistent() {
        #expect(BoardStyle.classic.dots == .all)
        #expect(BoardStyle.connected.dots == .connectedOnly)
        for style in BoardStyle.allCases where style.fillsItsCell {
            #expect(style.dots == .none, "\(style.displayName) has no room for dots")
        }
    }
}
