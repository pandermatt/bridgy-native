/// Chooses between several equally short routes.
///
/// These are the original `PredictiveConnectionAnalysator`'s four solution
/// modes, which exist because the shortest path is rarely unique and the choice
/// among equals leaks information about how strong the engine really is.
public enum PathTieBreak: String, Sendable, Hashable, Codable, CaseIterable {
    /// Prefer a cell touching none of its own groups. Keeps the position
    /// looking weak, which tempts a greedy opponent into over-attacking.
    case avoidConnection
    /// Prefer the cell that also does the most for its own shape.
    case disturbOpponent
    /// Prefer to extend the biggest group it already has, building one long chain.
    case longestConnection
    /// Pick at random.
    case random

    public var displayName: String {
        switch self {
        case .avoidConnection: return "Stay scattered"
        case .disturbOpponent: return "Interfere"
        case .longestConnection: return "Build long"
        case .random: return "Random"
        }
    }
}

/// Counts the moves each side still needs and plays on whichever route matters.
///
/// The strongest of the ported algorithms. Because the distance is exact, this
/// engine never misses a win it can reach, and never fails to see one coming.
public struct ShortestPathEngine: Engine {

    public let strategy: Strategy
    public let tieBreak: PathTieBreak

    public init(strategy: Strategy = .balanced, tieBreak: PathTieBreak = .avoidConnection) {
        self.strategy = strategy
        self.tieBreak = tieBreak
    }

    public var identifier: String { "path-\(strategy.rawValue)-\(tieBreak.rawValue)" }

    public var displayName: String {
        switch strategy {
        case .aggressive: return "Pathfinder, aggressive"
        case .defensive: return "Pathfinder, defensive"
        case .balanced: return "Pathfinder, balanced"
        }
    }

    public var summary: String {
        switch strategy {
        case .aggressive:
            return "Works out the fewest moves it needs to cross the board and plays them, ignoring you entirely."
        case .defensive:
            return "Works out the fewest moves you need and takes one of them away each turn."
        case .balanced:
            return "Counts the moves each of you still needs. If you are closer it cuts your route, otherwise it advances its own."
        }
    }

    public func chooseMove(in state: GameState, rng: inout SeededRandomNumberGenerator) -> Move? {
        guard !state.isOver else { return nil }
        let me = state.current
        let opponent = me.opponent

        let myGraph = PlayerGraph(board: state.board, player: me)
        let theirGraph = PlayerGraph(board: state.board, player: opponent)
        let mine = ShortestPath.search(in: state, for: me, graph: myGraph)
        let theirs = ShortestPath.search(in: state, for: opponent, graph: theirGraph)

        // Only a cell on somebody's shortest route can change either distance,
        // so this is the complete set of moves worth evaluating.
        var seen = Set<Int>()
        var candidates: [Int] = []
        for cell in mine.candidateCells + theirs.candidateCells where seen.insert(cell).inserted {
            candidates.append(cell)
        }
        guard !candidates.isEmpty else { return state.legalMoves.randomElement(using: &rng) }

        let unreachableCost = state.board.cellCount
        var bestScore = Int.min
        var tied: [Int] = []

        for cell in candidates {
            let myAfter = ShortestPath.distance(
                in: state, for: me, graph: myGraph, overriding: cell, as: me
            ) ?? unreachableCost
            let theirAfter = ShortestPath.distance(
                in: state, for: opponent, graph: theirGraph, overriding: cell, as: me
            ) ?? unreachableCost

            let score: Int
            switch strategy {
            case .aggressive:
                score = -myAfter
            case .defensive:
                score = theirAfter
            case .balanced:
                score = balancedScore(myAfter: myAfter, theirAfter: theirAfter)
            }

            if score > bestScore {
                bestScore = score
                tied = [cell]
            } else if score == bestScore {
                tied.append(cell)
            }
        }

        return select(from: tied, mover: me, in: state, rng: &rng)
    }

    /// Ranks a move by how far ahead it leaves me in the race.
    ///
    /// The plain difference is not enough on its own. Reaching "one move from
    /// winning" is worth nothing if a single reply undoes it, and the original
    /// algorithm lost games exactly that way — it would march to distance one,
    /// get blocked, march again, and never once interfere with its opponent.
    /// Winning outright and being about to lose are therefore judged first, and
    /// only then does the differential decide.
    private func balancedScore(myAfter: Int, theirAfter: Int) -> Int {
        if myAfter == 0 { return .max }                       // I have just won
        if theirAfter <= 1 { return Int.min / 2 + theirAfter - myAfter }  // they win next move
        return (theirAfter - myAfter) * 1_000
    }
    /// Applies the tie-break, always judged from the mover's point of view —
    /// even when the route being played on belongs to the opponent.
    private func select(
        from cells: [Int],
        mover: Player,
        in state: GameState,
        rng: inout SeededRandomNumberGenerator
    ) -> Move? {
        let moves = cells.map(state.board.move(at:))
        guard moves.count > 1 else { return moves.first }

        let graph = PlayerGraph(board: state.board, player: mover)
        var summary = ConnectionSummary(state: state, player: mover, graph: graph)

        switch tieBreak {
        case .random:
            return moves.randomElement(using: &rng)

        case .avoidConnection:
            let detached = moves.filter { !summary.touchesExistingComponent($0) }
            if let move = detached.randomElement(using: &rng) { return move }
            // Everything joins something, so join the smallest group instead.
            return moves.min { summary.neighbouringComponentSize($0) < summary.neighbouringComponentSize($1) }

        case .longestConnection:
            return moves.max { summary.neighbouringComponentSize($0) < summary.neighbouringComponentSize($1) }

        case .disturbOpponent:
            return moves.max { summary.rate($0) < summary.rate($1) }
        }
    }
}
