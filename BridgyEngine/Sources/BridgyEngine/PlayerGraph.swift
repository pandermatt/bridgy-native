/// The graph a single player is trying to cross.
///
/// Nodes are that player's dots plus two virtual terminals (`source` and
/// `sink`). Every cell of the board appears as one edge; terminal edges carry
/// a cell of `-1` because they are free — they represent already being on the
/// goal line rather than a move that has to be played.
public struct PlayerGraph: Sendable {

    public struct Edge: Sendable {
        public let node: Int
        /// Index into `GameState.cells`, or `-1` for a free terminal edge.
        public let cell: Int
    }

    public let board: Board
    public let player: Player
    public let dotCount: Int
    public let source: Int
    public let sink: Int
    public let nodeCount: Int
    public let neighbors: [[Edge]]

    public init(board: Board, player: Player) {
        self.board = board
        self.player = player
        let dots = board.dotCount(for: player)
        self.dotCount = dots
        self.source = dots
        self.sink = dots + 1
        self.nodeCount = dots + 2

        var adjacency = [[Edge]](repeating: [], count: dots + 2)
        for cell in 0..<board.cellCount {
            let move = board.move(at: cell)
            let (a, b) = board.endpoints(move, for: player)
            adjacency[a].append(Edge(node: b, cell: cell))
            adjacency[b].append(Edge(node: a, cell: cell))
        }

        let n = board.size
        switch player {
        case .blue:
            for col in 0..<n {
                let top = board.blueDot(row: 0, col: col)
                let bottom = board.blueDot(row: n, col: col)
                adjacency[dots].append(Edge(node: top, cell: -1))
                adjacency[top].append(Edge(node: dots, cell: -1))
                adjacency[dots + 1].append(Edge(node: bottom, cell: -1))
                adjacency[bottom].append(Edge(node: dots + 1, cell: -1))
            }
        case .red:
            for row in 0..<n {
                let left = board.redDot(row: row, col: 0)
                let right = board.redDot(row: row, col: n)
                adjacency[dots].append(Edge(node: left, cell: -1))
                adjacency[left].append(Edge(node: dots, cell: -1))
                adjacency[dots + 1].append(Edge(node: right, cell: -1))
                adjacency[right].append(Edge(node: dots + 1, cell: -1))
            }
        }
        self.neighbors = adjacency
    }

    /// The coordinate that measures progress: row for blue, column for red.
    public func major(ofDot dot: Int) -> Int {
        player == .blue ? dot / board.size : dot % (board.size + 1)
    }
}
