import Foundation
/// Monte Carlo tree search with UCT and RAVE.
///
/// Bridg-It suits Monte Carlo methods unusually well. A random playout needs no
/// stopping rule: because the game admits no draws, and because extra edges can
/// never destroy a connection that already exists, the winner of a completely
/// filled board *is* the winner of the game. A playout is therefore a shuffle of
/// the empty cells followed by a single union-find pass.
public struct MCTSEngine: Engine {

    /// Fixed number of playouts. Set this for reproducible play; leave it `nil`
    /// to think for `timeBudget` instead.
    public let iterations: Int?
    /// Wall-clock budget, used when `iterations` is `nil`.
    public let timeBudget: Duration
    /// UCT exploration weight.
    public let explorationConstant: Double
    /// RAVE equivalence parameter: how quickly the all-moves-as-first estimate
    /// gives way to real visit statistics.
    public let raveBias: Double

    public init(
        iterations: Int? = nil,
        timeBudget: Duration = .milliseconds(1_000),
        explorationConstant: Double = 1.4,
        raveBias: Double = 0.05
    ) {
        self.iterations = iterations
        self.timeBudget = timeBudget
        self.explorationConstant = explorationConstant
        self.raveBias = raveBias
    }

    public var identifier: String { "mcts" }
    public let displayName = "Monte Carlo"
    public let summary =
        "Plays out thousands of random finishes each turn and follows the lines that win most often. "
        + "It has no built-in theory of the game, only experience of it."

    /// RAVE bookkeeping is skipped below this depth, where it costs more than it
    /// is worth on a wide board.
    private static let raveDepthLimit = 2

    private final class Node {
        let move: Move?
        /// Who played `move`. `nil` at the root.
        let mover: Player?
        /// Whose turn it is in this position.
        let toMove: Player
        var children: [Node] = []
        var untried: [Int]
        var visits = 0
        var wins = 0.0
        var raveVisits = 0
        var raveWins = 0.0

        init(move: Move?, mover: Player?, toMove: Player, untried: [Int]) {
            self.move = move
            self.mover = mover
            self.toMove = toMove
            self.untried = untried
        }
    }

    public func chooseMove(in state: GameState, rng: inout SeededRandomNumberGenerator) -> Move? {
        guard !state.isOver else { return nil }
        let me = state.current

        // Cheap safety net. Search would usually find these anyway, but "usually"
        // is not good enough for a move the player can see at a glance.
        if let decisive = decisiveMove(in: state, for: me) { return decisive }

        let root = Node(
            move: nil,
            mover: nil,
            toMove: me,
            untried: state.legalMoveIndices.shuffled(using: &rng)
        )

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeBudget)
        var performed = 0

        while !Task.isCancelled {
            if let iterations {
                if performed >= iterations { break }
            } else if clock.now >= deadline {
                break
            }
            performed += 1
            runIteration(from: root, state: state, rng: &rng)
        }

        // The most-visited child is the robust choice; the highest-scoring one
        // can be an outlier the search never got round to disproving.
        return root.children.max { lhs, rhs in
            lhs.visits == rhs.visits ? lhs.wins < rhs.wins : lhs.visits < rhs.visits
        }?.move ?? state.legalMoves.randomElement(using: &rng)
    }

    /// A move that wins immediately, or that stops the opponent winning immediately.
    private func decisiveMove(in state: GameState, for me: Player) -> Move? {
        var block: Move?
        for cell in 0..<state.board.cellCount where state.cells[cell] == nil {
            let move = state.board.move(at: cell)
            if state.wouldWin(move, for: me) { return move }
            if block == nil, state.wouldWin(move, for: me.opponent) { block = move }
        }
        return block
    }

    private func runIteration(
        from root: Node,
        state: GameState,
        rng: inout SeededRandomNumberGenerator
    ) {
        var position = state
        var path = [root]
        var node = root

        // Selection.
        while node.untried.isEmpty, !node.children.isEmpty, !position.isOver {
            guard let chosen = bestChild(of: node) else { break }
            node = chosen
            position.apply(chosen.move!)
            path.append(chosen)
        }

        // Expansion.
        if !position.isOver, let cell = node.untried.popLast() {
            let move = position.board.move(at: cell)
            let mover = position.current
            position.apply(move)
            let child = Node(
                move: move,
                mover: mover,
                toMove: position.current,
                untried: position.isOver ? [] : position.legalMoveIndices.shuffled(using: &rng)
            )
            node.children.append(child)
            path.append(child)
        }

        // Simulation.
        let result = Playout.run(from: position, rng: &rng)
        backPropagate(path: path, board: state.board, winner: result.winner, playout: result)
    }

    private func bestChild(of node: Node) -> Node? {
        let logVisits = log(Double(max(node.visits, 1)))
        var best: Node?
        var bestScore = -Double.infinity
        for child in node.children {
            let exploitation: Double
            if child.visits == 0 {
                exploitation = 0.5
            } else {
                let mean = child.wins / Double(child.visits)
                if child.raveVisits > 0 {
                    let visits = Double(child.visits)
                    let rave = Double(child.raveVisits)
                    // Gelly & Silver's beta: trust RAVE early, real visits later.
                    let beta = rave / (rave + visits + 4.0 * raveBias * raveBias * rave * visits)
                    exploitation = (1 - beta) * mean + beta * (child.raveWins / rave)
                } else {
                    exploitation = mean
                }
            }
            let exploration = child.visits == 0
                ? Double.greatestFiniteMagnitude
                : explorationConstant * (logVisits / Double(child.visits)).squareRoot()
            let score = exploitation + exploration
            if score > bestScore {
                bestScore = score
                best = child
            }
        }
        return best
    }

    private func backPropagate(path: [Node], board: Board, winner: Player, playout: Playout.Result) {
        var blueCells = playout.blueCells
        var redCells = playout.redCells

        for depth in stride(from: path.count - 1, through: 0, by: -1) {
            let node = path[depth]
            node.visits += 1
            if let mover = node.mover, mover == winner { node.wins += 1 }

            if depth <= Self.raveDepthLimit {
                let played = node.toMove == .blue ? blueCells : redCells
                let credit = node.toMove == winner ? 1.0 : 0.0
                for child in node.children {
                    guard let move = child.move else { continue }
                    if played.contains(board.index(of: move)) {
                        child.raveVisits += 1
                        child.raveWins += credit
                    }
                }
            }

            // Stepping up a level: this node's own move now counts as "played
            // later" from the parent's point of view.
            if let move = node.move, let mover = node.mover {
                if mover == .blue {
                    blueCells.insert(board.index(of: move))
                } else {
                    redCells.insert(board.index(of: move))
                }
            }
        }
    }
}

/// Fills a position at random and reports who ends up connected.
enum Playout {

    struct Result {
        let winner: Player
        let blueCells: Set<Int>
        let redCells: Set<Int>
    }

    /// Completes `state` by dealing the remaining cells out at random.
    ///
    /// Filling the board rather than stopping at the first win is safe: a
    /// connection cannot be undone by later moves, and the two players cannot
    /// both be connected, so the full board has the same winner as the game.
    static func run(from state: GameState, rng: inout SeededRandomNumberGenerator) -> Result {
        var owners = state.cells
        var blueCells = Set<Int>()
        var redCells = Set<Int>()

        if let decided = state.winner {
            for cell in 0..<state.board.cellCount where owners[cell] != nil {
                if owners[cell] == .blue { blueCells.insert(cell) } else { redCells.insert(cell) }
            }
            return Result(winner: decided, blueCells: blueCells, redCells: redCells)
        }

        var empty = state.cells.indices.filter { owners[$0] == nil }
        empty.shuffle(using: &rng)
        var turn = state.current
        for cell in empty {
            owners[cell] = turn
            if turn == .blue { blueCells.insert(cell) } else { redCells.insert(cell) }
            turn = turn.opponent
        }

        // Only blue needs checking: exactly one player crosses a filled board.
        let board = state.board
        var blue = DisjointSet(count: board.blueDotCount + 2)
        let top = board.blueDotCount
        let bottom = board.blueDotCount + 1
        for col in 0..<board.size {
            blue.union(board.blueDot(row: 0, col: col), top)
            blue.union(board.blueDot(row: board.size, col: col), bottom)
        }
        for cell in 0..<board.cellCount where owners[cell] == .blue {
            let (a, b) = board.blueEndpoints(board.move(at: cell))
            blue.union(a, b)
        }
        let winner: Player = blue.connected(top, bottom) ? .blue : .red
        return Result(winner: winner, blueCells: blueCells, redCells: redCells)
    }
}
