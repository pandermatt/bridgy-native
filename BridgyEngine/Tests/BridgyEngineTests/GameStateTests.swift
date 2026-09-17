import Testing
@testable import BridgyEngine

@Suite("Game state")
struct GameStateTests {

    /// Independently re-derives connectivity for a fully assigned board, so the
    /// no-draw check does not simply reuse `GameState`'s own bookkeeping.
    private func winners(ofFullAssignment owners: [Player], board: Board) -> Set<Player> {
        var blue = DisjointSet(count: board.blueDotCount + 2)
        var red = DisjointSet(count: board.redDotCount + 2)
        let n = board.size
        for col in 0..<n {
            blue.union(board.blueDot(row: 0, col: col), board.blueDotCount)
            blue.union(board.blueDot(row: n, col: col), board.blueDotCount + 1)
        }
        for row in 0..<n {
            red.union(board.redDot(row: row, col: 0), board.redDotCount)
            red.union(board.redDot(row: row, col: n), board.redDotCount + 1)
        }
        for (index, owner) in owners.enumerated() {
            let move = board.move(at: index)
            if owner == .blue {
                let (a, b) = board.blueEndpoints(move)
                blue.union(a, b)
            } else {
                let (a, b) = board.redEndpoints(move)
                red.union(a, b)
            }
        }
        var result: Set<Player> = []
        if blue.connected(board.blueDotCount, board.blueDotCount + 1) { result.insert(.blue) }
        if red.connected(board.redDotCount, board.redDotCount + 1) { result.insert(.red) }
        return result
    }

    @Test("A fully assigned board always has exactly one winner", arguments: 2...8)
    func noDraws(size: Int) {
        let board = Board(size: size)
        var rng = SeededRandomNumberGenerator(seed: UInt64(size) &* 7919)
        for _ in 0..<200 {
            let owners = (0..<board.cellCount).map { _ in
                Bool.random(using: &rng) ? Player.blue : Player.red
            }
            let result = winners(ofFullAssignment: owners, board: board)
            #expect(result.count == 1, "size \(size): expected exactly one winner, got \(result)")
        }
    }

    @Test("Blue opens and players alternate")
    func turnOrder() {
        var state = GameState(size: 4)
        #expect(state.current == .blue)
        let first = state.apply(Move(kind: .v, row: 0, col: 0))
        #expect(first)
        #expect(state.current == .red)
        let second = state.apply(Move(kind: .v, row: 0, col: 1))
        #expect(second)
        #expect(state.current == .blue)
    }

    @Test("A cell cannot be taken twice, by either player")
    func cellsAreContested() {
        var state = GameState(size: 4)
        let move = Move(kind: .v, row: 1, col: 1)
        let claimed = state.apply(move)
        #expect(claimed)
        #expect(state.owner(of: move) == .blue)
        #expect(state.isLegal(move) == false)
        let reclaimed = state.apply(move)
        #expect(reclaimed == false, "red must not be able to reuse blue's cell")
    }

    @Test("Blue wins on a straight vertical run")
    func blueWinsVertically() {
        var state = GameState(size: 3)
        // Blue takes column 0 top to bottom; red plays harmlessly far away.
        let blueMoves = (0..<3).map { Move(kind: .v, row: $0, col: 0) }
        let redMoves = [Move(kind: .v, row: 0, col: 2), Move(kind: .v, row: 1, col: 2)]
        for (index, move) in blueMoves.enumerated() {
            let played = state.apply(move)
            #expect(played)
            if state.isOver { break }
            let reply = state.apply(redMoves[index])
            #expect(reply)
        }
        #expect(state.winner == .blue)
        #expect(state.isOver)
        #expect(state.legalMoves.isEmpty, "no moves remain once the game is decided")
    }

    @Test("Red wins on a straight horizontal run")
    func redWinsHorizontally() {
        var state = GameState(size: 3)
        // Red takes row 0 left to right using the .v family; blue dawdles in row 2.
        let script = [
            Move(kind: .v, row: 2, col: 0),  // blue
            Move(kind: .v, row: 0, col: 0),  // red
            Move(kind: .v, row: 2, col: 1),  // blue
            Move(kind: .v, row: 0, col: 1),  // red
            Move(kind: .v, row: 2, col: 2),  // blue
            Move(kind: .v, row: 0, col: 2)   // red
        ]
        for move in script {
            let played = state.apply(move)
            #expect(played)
        }
        #expect(state.winner == .red)
    }

    @Test("wouldWin agrees with actually playing the move", arguments: 2...6)
    func wouldWinIsAccurate(size: Int) {
        var rng = SeededRandomNumberGenerator(seed: UInt64(size) &* 104_729)
        for _ in 0..<60 {
            var state = GameState(size: size)
            while !state.isOver {
                let candidates = state.legalMoves
                guard let move = candidates.randomElement(using: &rng) else { break }
                let predicted = state.wouldWin(move, for: state.current)
                var probe = state
                probe.apply(move)
                #expect(predicted == (probe.winner != nil))
                state = probe
            }
        }
    }

    @Test("Every random playout terminates with a winner", arguments: 2...8)
    func playoutsTerminate(size: Int) {
        let board = Board(size: size)
        var rng = SeededRandomNumberGenerator(seed: UInt64(size) &* 31)
        for _ in 0..<50 {
            var state = GameState(size: size)
            while !state.isOver, let move = state.legalMoves.randomElement(using: &rng) {
                state.apply(move)
            }
            #expect(state.winner != nil)
            #expect(state.moveCount <= board.cellCount)
        }
    }

    @Test("Undo restores the previous position exactly", arguments: 2...8)
    func undoRestores(size: Int) {
        var rng = SeededRandomNumberGenerator(seed: UInt64(size) &* 65_537)
        let fresh = GameState(size: size)
        var state = fresh
        var snapshots: [GameState] = []
        while !state.isOver, let move = state.legalMoves.randomElement(using: &rng) {
            snapshots.append(state)
            state.apply(move)
        }
        while let expected = snapshots.popLast() {
            state.undo()
            #expect(state == expected)
        }
        #expect(state == fresh)
        #expect(state.canUndo == false)
        let nothingLeft = state.undo()
        #expect(nothingLeft == nil)
    }
}
