/// Cached connectivity for one player, used to rate candidate moves cheaply.
///
/// This is the idea behind the original's `PerformantBasicConnectionEvaluator`:
/// rather than walking a connection from scratch for every candidate (as
/// `BasicConnectionEvaluator` did, recursively), build the player's components
/// once per turn and then rate a candidate by merging two summaries.
public struct ConnectionSummary: Sendable {

    /// How good a candidate cell looks.
    public struct Rating: Sendable, Comparable {
        /// Extent of the merged component along the player's winning axis:
        /// rows for blue, columns for red. `span == board.size` means a win.
        public let span: Int
        /// How many cells the merged component would contain.
        public let elements: Int

        public static func < (lhs: Rating, rhs: Rating) -> Bool {
            lhs.span == rhs.span ? lhs.elements < rhs.elements : lhs.span < rhs.span
        }
    }

    private let graph: PlayerGraph
    private var sets: DisjointSet
    private var minMajor: [Int]
    private var maxMajor: [Int]
    private var cellCount: [Int]

    /// Builds the components `player` currently owns.
    public init(state: GameState, player: Player, graph: PlayerGraph) {
        self.graph = graph
        let dots = graph.dotCount
        var sets = DisjointSet(count: dots)
        for cell in 0..<state.board.cellCount where state.cells[cell] == player {
            let (a, b) = state.board.endpoints(state.board.move(at: cell), for: player)
            sets.union(a, b)
        }

        var minMajor = [Int](repeating: Int.max, count: dots)
        var maxMajor = [Int](repeating: Int.min, count: dots)
        var cellCount = [Int](repeating: 0, count: dots)
        for dot in 0..<dots {
            let root = sets.find(dot)
            let major = graph.major(ofDot: dot)
            minMajor[root] = min(minMajor[root], major)
            maxMajor[root] = max(maxMajor[root], major)
        }
        for cell in 0..<state.board.cellCount where state.cells[cell] == player {
            let (a, _) = state.board.endpoints(state.board.move(at: cell), for: player)
            cellCount[sets.find(a)] += 1
        }

        self.sets = sets
        self.minMajor = minMajor
        self.maxMajor = maxMajor
        self.cellCount = cellCount
    }

    /// Rates the component that would result from taking `move`.
    public mutating func rate(_ move: Move) -> Rating {
        let (a, b) = graph.board.endpoints(move, for: graph.player)
        let rootA = sets.find(a)
        let rootB = sets.find(b)
        let low = min(minMajor[rootA], minMajor[rootB])
        let high = max(maxMajor[rootA], maxMajor[rootB])
        let merged = rootA == rootB
            ? cellCount[rootA]
            : cellCount[rootA] + cellCount[rootB]
        return Rating(span: high - low, elements: merged + 1)
    }

    /// Whether `move` would touch a component this player already owns.
    ///
    /// Used by the shortest-path engine's "avoid connection" tie-break.
    public mutating func touchesExistingComponent(_ move: Move) -> Bool {
        let (a, b) = graph.board.endpoints(move, for: graph.player)
        return cellCount[sets.find(a)] > 0 || cellCount[sets.find(b)] > 0
    }

    /// Size, in cells, of the largest component either endpoint belongs to.
    public mutating func neighbouringComponentSize(_ move: Move) -> Int {
        let (a, b) = graph.board.endpoints(move, for: graph.player)
        return max(cellCount[sets.find(a)], cellCount[sets.find(b)])
    }
}
