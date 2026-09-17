import Testing
@testable import BridgyEngine

@Suite("Winning path")
struct WinningPathTests {

    /// Plays a real game out and hands back the finished position.
    private func finishedGame(size: Int, seed: UInt64) -> GameState {
        var rng = SeededRandomNumberGenerator(seed: seed)
        return Match.play(
            size: size,
            blue: ShortestPathEngine(strategy: .balanced),
            red: GreedyEngine(strategy: .balanced),
            rng: &rng
        )
    }

    @Test("An unfinished board has no winning path")
    func emptyWhileRunning() {
        let state = GameState(size: 6)
        #expect(WinningPath.forWinner(of: state).isEmpty)
        #expect(WinningPath.cells(
            in: state,
            for: .blue,
            graph: PlayerGraph(board: state.board, player: .blue)
        ).isEmpty)
    }

    @Test("The path is made only of the winner's own cells", arguments: [4, 6, 9])
    func ownedByTheWinner(size: Int) {
        let state = finishedGame(size: size, seed: 7)
        let winner = try! #require(state.winner)
        let path = WinningPath.forWinner(of: state)

        #expect(!path.isEmpty)
        for cell in path {
            #expect(state.cells[cell] == winner, "cell \(cell) is not the winner's")
        }
        #expect(Set(path).count == path.count, "the path repeats a cell")
    }

    /// The real structural claim: it is a *chain*. Each step has to share a dot
    /// with the next, and the two ends have to touch the winner's goal lines —
    /// otherwise it is just a bag of cells that happen to be owned.
    @Test("The path is a connected chain from one goal line to the other", arguments: [4, 6, 9])
    func formsAChain(size: Int) {
        let state = finishedGame(size: size, seed: 7)
        let winner = try! #require(state.winner)
        let board = state.board
        let path = WinningPath.forWinner(of: state)

        let graph = PlayerGraph(board: board, player: winner)
        // The free terminal edges are deliberately not in the path, so the chain
        // runs dot-to-dot: it starts on a dot sitting on the near goal line and
        // has to end on one sitting on the far line.
        let onNearLine = Set(graph.neighbors[graph.source].filter { $0.cell < 0 }.map(\.node))
        let onFarLine = Set(graph.neighbors[graph.sink].filter { $0.cell < 0 }.map(\.node))

        let first = try! #require(path.first)
        let (a, b) = board.endpoints(board.move(at: first), for: winner)
        var node = onNearLine.contains(a) ? a : b
        #expect(onNearLine.contains(node), "the chain does not start on the near goal line")

        for cell in path {
            let (a, b) = board.endpoints(board.move(at: cell), for: winner)
            #expect(a == node || b == node, "cell \(cell) does not continue the chain")
            node = (a == node) ? b : a
        }

        #expect(onFarLine.contains(node), "the chain does not reach the far goal line")
    }

    @Test("The loser has no path")
    func loserHasNone() {
        let state = finishedGame(size: 6, seed: 7)
        let winner = try! #require(state.winner)
        let loser: Player = winner == .blue ? .red : .blue
        let path = WinningPath.cells(
            in: state,
            for: loser,
            graph: PlayerGraph(board: state.board, player: loser)
        )
        #expect(path.isEmpty, "both players cannot have crossed")
    }

    @Test("Building the graph on demand agrees with reusing one")
    func movesMatchCells() {
        let state = finishedGame(size: 6, seed: 11)
        let winner = try! #require(state.winner)
        let graph = PlayerGraph(board: state.board, player: winner)
        let cells = WinningPath.cells(in: state, for: winner, graph: graph)
        #expect(WinningPath.moves(in: state, for: winner) == cells.map { state.board.move(at: $0) })
    }
}
