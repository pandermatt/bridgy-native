import Testing
@testable import BridgyEngine

@Suite("Board geometry")
struct BoardTests {

    @Test("Cell count is n² + (n-1)², and always odd", arguments: 2...35)
    func cellCount(size: Int) {
        let board = Board(size: size)
        #expect(board.cellCount == size * size + (size - 1) * (size - 1))
        #expect(board.cellCount == 2 * size * size - 2 * size + 1)
        #expect(board.cellCount % 2 == 1, "blue must get exactly one move more than red")
    }

    @Test("index(of:) and move(at:) round-trip over every cell", arguments: 2...20)
    func indexRoundTrip(size: Int) {
        let board = Board(size: size)
        for index in 0..<board.cellCount {
            let move = board.move(at: index)
            #expect(board.contains(move))
            #expect(board.index(of: move) == index)
        }
        #expect(Set(board.allMoves).count == board.cellCount, "no duplicate cells")
    }

    @Test("Every cell joins two distinct, in-range dots for both players", arguments: 2...20)
    func endpointsAreValid(size: Int) {
        let board = Board(size: size)
        for move in board.allMoves {
            let (b0, b1) = board.blueEndpoints(move)
            #expect(b0 != b1)
            #expect((0..<board.blueDotCount).contains(b0))
            #expect((0..<board.blueDotCount).contains(b1))

            let (r0, r1) = board.redEndpoints(move)
            #expect(r0 != r1)
            #expect((0..<board.redDotCount).contains(r0))
            #expect((0..<board.redDotCount).contains(r1))
        }
    }

    @Test("Distinct cells draw distinct edges for each player", arguments: 2...20)
    func edgesAreDistinct(size: Int) {
        let board = Board(size: size)
        var blueEdges = Set<[Int]>()
        var redEdges = Set<[Int]>()
        for move in board.allMoves {
            let (b0, b1) = board.blueEndpoints(move)
            let (r0, r1) = board.redEndpoints(move)
            #expect(blueEdges.insert([min(b0, b1), max(b0, b1)]).inserted)
            #expect(redEdges.insert([min(r0, r1), max(r0, r1)]).inserted)
        }
    }

    @Test("Blue and red edges through a cell cross at its centre", arguments: 2...12)
    func edgesCrossAtCentre(size: Int) {
        let board = Board(size: size)
        for move in board.allMoves {
            let centre = board.center(of: move)

            let (b0, b1) = board.blueEndpoints(move)
            let bp0 = board.blueDotPosition(row: b0 / size, col: b0 % size)
            let bp1 = board.blueDotPosition(row: b1 / size, col: b1 % size)
            #expect((bp0.x + bp1.x) / 2 == centre.x)
            #expect((bp0.y + bp1.y) / 2 == centre.y)

            let (r0, r1) = board.redEndpoints(move)
            let rp0 = board.redDotPosition(row: r0 / (size + 1), col: r0 % (size + 1))
            let rp1 = board.redDotPosition(row: r1 / (size + 1), col: r1 % (size + 1))
            #expect((rp0.x + rp1.x) / 2 == centre.x)
            #expect((rp0.y + rp1.y) / 2 == centre.y)
        }
    }

    @Test("Every cell sits strictly inside the lattice", arguments: 2...20)
    func centresAreInBounds(size: Int) {
        let board = Board(size: size)
        for move in board.allMoves {
            let centre = board.center(of: move)
            #expect((1..<board.span).contains(centre.x))
            #expect((1..<board.span).contains(centre.y))
        }
    }
}
