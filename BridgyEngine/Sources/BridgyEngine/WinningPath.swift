/// The chain that actually won the game.
///
/// The disjoint sets know *that* a player has crossed, because they only ever
/// store a representative — they cannot say which cells did it. `ShortestPath`
/// cannot answer either: it reports the empty cells still needed, so on a
/// finished board the winner's route comes back empty.
///
/// So this walks the player's own graph: a plain breadth-first search from their
/// source terminal to their sink, allowed to cross only cells they already own.
/// One pass, `O(nodes + edges)`.
public enum WinningPath {

    /// Indices into `GameState.cells` forming one chain from `player`'s source
    /// to their sink, or empty when they have not crossed.
    ///
    /// Breadth-first, so it is the shortest such chain: a player who has
    /// meandered gets the spine of the win rather than every cell they own.
    public static func cells(
        in state: GameState,
        for player: Player,
        graph: PlayerGraph
    ) -> [Int] {
        var parentNode = [Int](repeating: -1, count: graph.nodeCount)
        var parentCell = [Int](repeating: -1, count: graph.nodeCount)
        var visited = [Bool](repeating: false, count: graph.nodeCount)

        var queue = IntDeque(minimumCapacity: graph.nodeCount)
        queue.pushBack(graph.source)
        visited[graph.source] = true

        while let node = queue.popFront() {
            if node == graph.sink { break }
            for edge in graph.neighbors[node] where !visited[edge.node] {
                // A cell of -1 is a free terminal edge: being on the goal line
                // already, rather than a move anyone had to play.
                guard edge.cell < 0 || state.cells[edge.cell] == player else { continue }
                visited[edge.node] = true
                parentNode[edge.node] = node
                parentCell[edge.node] = edge.cell
                queue.pushBack(edge.node)
            }
        }

        guard visited[graph.sink] else { return [] }

        var chain: [Int] = []
        var node = graph.sink
        while node != graph.source {
            if parentCell[node] >= 0 { chain.append(parentCell[node]) }
            node = parentNode[node]
        }
        return chain.reversed()
    }

    /// The same chain as moves, building the graph on demand.
    ///
    /// Convenient for a one-shot caller such as a finished-game picture; a
    /// caller that already holds a `PlayerGraph` should use `cells` instead
    /// rather than pay to build another.
    public static func moves(in state: GameState, for player: Player) -> [Move] {
        let graph = PlayerGraph(board: state.board, player: player)
        return cells(in: state, for: player, graph: graph).map { state.board.move(at: $0) }
    }

    /// The winner's chain, or empty while the game is still running.
    public static func forWinner(of state: GameState) -> [Int] {
        guard let winner = state.winner else { return [] }
        let graph = PlayerGraph(board: state.board, player: winner)
        return cells(in: state, for: winner, graph: graph)
    }
}
