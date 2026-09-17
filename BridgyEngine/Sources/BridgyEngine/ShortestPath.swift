/// How many moves a player still needs, and which cells could matter.
///
/// This is the heart of the original `PredictiveAlgorithm`, expressed directly:
/// on that player's graph, a cell they already own is free, an empty cell costs
/// one move, and a cell the opponent holds is impassable. The distance from
/// `source` to `sink` is therefore exactly "moves left to win".
///
/// Distances are run both ways, which gives something the original never had:
/// the full set of cells lying on *some* shortest route. A cell outside that
/// set can never raise the player's distance, so it is the complete candidate
/// list for blocking them — and searching only those cells is what keeps the
/// engine fast on a 35x35 board.
public struct ShortestPath: Sendable {

    /// Moves still required. `nil` when the opponent has already cut every route.
    public let distance: Int?
    /// Empty cells along one shortest route, in order.
    public let requiredCells: [Int]
    /// Every empty cell that lies on at least one shortest route.
    public let candidateCells: [Int]

    static let unreachable = Int.max

    /// 0-1 BFS from `origin`, optionally pretending one cell has a different owner.
    static func distances(
        in state: GameState,
        for player: Player,
        graph: PlayerGraph,
        from origin: Int,
        overriding overrideCell: Int = -1,
        as overrideOwner: Player? = nil,
        parentNode: inout [Int],
        parentCell: inout [Int]
    ) -> [Int] {
        var distance = [Int](repeating: unreachable, count: graph.nodeCount)
        parentNode = [Int](repeating: -1, count: graph.nodeCount)
        parentCell = [Int](repeating: -1, count: graph.nodeCount)

        var queue = IntDeque(minimumCapacity: graph.nodeCount * 2)
        distance[origin] = 0
        queue.pushFront(origin)

        while let node = queue.popFront() {
            let base = distance[node]
            if base == unreachable { continue }
            for edge in graph.neighbors[node] {
                let owner: Player?
                if edge.cell < 0 {
                    owner = nil
                } else if edge.cell == overrideCell {
                    owner = overrideOwner
                } else {
                    owner = state.cells[edge.cell]
                }
                if let owner, owner != player { continue }
                let step = (edge.cell < 0 || owner == player) ? 0 : 1
                let candidate = base + step
                if candidate < distance[edge.node] {
                    distance[edge.node] = candidate
                    parentNode[edge.node] = node
                    parentCell[edge.node] = edge.cell
                    if step == 0 { queue.pushFront(edge.node) } else { queue.pushBack(edge.node) }
                }
            }
        }
        return distance
    }

    /// Moves `player` needs, assuming `overrideCell` belongs to `overrideOwner`.
    public static func distance(
        in state: GameState,
        for player: Player,
        graph: PlayerGraph,
        overriding overrideCell: Int = -1,
        as overrideOwner: Player? = nil
    ) -> Int? {
        var parentNode: [Int] = []
        var parentCell: [Int] = []
        let forward = distances(
            in: state, for: player, graph: graph, from: graph.source,
            overriding: overrideCell, as: overrideOwner,
            parentNode: &parentNode, parentCell: &parentCell
        )
        let result = forward[graph.sink]
        return result == unreachable ? nil : result
    }

    /// Full analysis for `player`: distance, one concrete route, and every cell
    /// that could lie on a shortest route.
    public static func search(in state: GameState, for player: Player, graph: PlayerGraph) -> ShortestPath {
        var forwardParentNode: [Int] = []
        var forwardParentCell: [Int] = []
        let forward = distances(
            in: state, for: player, graph: graph, from: graph.source,
            parentNode: &forwardParentNode, parentCell: &forwardParentCell
        )
        guard forward[graph.sink] != unreachable else {
            return ShortestPath(distance: nil, requiredCells: [], candidateCells: [])
        }
        let total = forward[graph.sink]

        var backwardParentNode: [Int] = []
        var backwardParentCell: [Int] = []
        let backward = distances(
            in: state, for: player, graph: graph, from: graph.sink,
            parentNode: &backwardParentNode, parentCell: &backwardParentCell
        )

        // One concrete route, walked back from the sink.
        var route: [Int] = []
        var node = graph.sink
        while node != graph.source {
            let cell = forwardParentCell[node]
            if cell >= 0, state.cells[cell] == nil { route.append(cell) }
            node = forwardParentNode[node]
            if node < 0 { break }
        }

        // Every empty cell that some shortest route passes through.
        var candidates: [Int] = []
        for cell in 0..<state.board.cellCount where state.cells[cell] == nil {
            let (a, b) = state.board.endpoints(state.board.move(at: cell), for: player)
            guard forward[a] != unreachable || forward[b] != unreachable else { continue }
            let forwardThenBack = forward[a] == unreachable || backward[b] == unreachable
                ? unreachable : forward[a] + 1 + backward[b]
            let backThenForward = forward[b] == unreachable || backward[a] == unreachable
                ? unreachable : forward[b] + 1 + backward[a]
            if min(forwardThenBack, backThenForward) == total { candidates.append(cell) }
        }

        return ShortestPath(distance: total, requiredCells: route.reversed(), candidateCells: candidates)
    }

    init(distance: Int?, requiredCells: [Int], candidateCells: [Int]) {
        self.distance = distance
        self.requiredCells = requiredCells
        self.candidateCells = candidateCells
    }

    /// Moves `player` still needs in `state`, for hints and status text.
    public static func movesToWin(in state: GameState, for player: Player) -> Int? {
        let graph = PlayerGraph(board: state.board, player: player)
        return distance(in: state, for: player, graph: graph)
    }
}
