/// Rates every empty cell by the connection it would create and takes the best.
///
/// This is the original's `SimpleAlgorithm` and `PerformantAlgorithm` merged:
/// they scored positions identically and differed only in whether the work was
/// cached, so there is one engine here and the caching is simply always on.
///
/// The scoring needs no special case for winning or losing moves. A component's
/// span reaches `board.size` exactly when it crosses the board, so a winning
/// move always rates highest, and — played defensively — the opponent's winning
/// move is always the one worth blocking.
public struct GreedyEngine: Engine {

    public let strategy: Strategy

    public init(strategy: Strategy) {
        self.strategy = strategy
    }

    public var identifier: String { "greedy-\(strategy.rawValue)" }

    public var displayName: String {
        switch strategy {
        case .aggressive: return "Greedy, aggressive"
        case .defensive: return "Greedy, defensive"
        case .balanced: return "Greedy, balanced"
        }
    }

    public var summary: String {
        switch strategy {
        case .aggressive:
            return "Always extends its own longest connection and never looks at yours. Easy to trap."
        case .defensive:
            return "Only blocks. It works out your strongest move and takes that cell, ignoring its own connection."
        case .balanced:
            return "Weighs its own best connection against yours and either extends or blocks, whichever matters more."
        }
    }

    public func chooseMove(in state: GameState, rng: inout SeededRandomNumberGenerator) -> Move? {
        guard !state.isOver else { return nil }
        let me = state.current
        switch strategy {
        case .aggressive:
            return best(for: me, in: state, rng: &rng)?.move
        case .defensive:
            return best(for: me.opponent, in: state, rng: &rng)?.move
        case .balanced:
            let mine = best(for: me, in: state, rng: &rng)
            let theirs = best(for: me.opponent, in: state, rng: &rng)
            guard let mine else { return theirs?.move }
            guard let theirs else { return mine.move }
            // Ties go to extending: it is my turn, so being level means I am ahead.
            return theirs.rating > mine.rating ? theirs.move : mine.move
        }
    }

    private struct Candidate {
        let move: Move
        let rating: ConnectionSummary.Rating
    }

    /// Best cell for `player`, breaking ties at random as the original did.
    private func best(
        for player: Player,
        in state: GameState,
        rng: inout SeededRandomNumberGenerator
    ) -> Candidate? {
        let graph = PlayerGraph(board: state.board, player: player)
        var summary = ConnectionSummary(state: state, player: player, graph: graph)
        var bestRating: ConnectionSummary.Rating?
        var tied: [Move] = []

        for cell in 0..<state.board.cellCount where state.cells[cell] == nil {
            let move = state.board.move(at: cell)
            let rating = summary.rate(move)
            if bestRating == nil || rating > bestRating! {
                bestRating = rating
                tied = [move]
            } else if rating == bestRating! {
                tied.append(move)
            }
        }

        guard let bestRating, let move = tied.randomElement(using: &rng) else { return nil }
        return Candidate(move: move, rating: bestRating)
    }
}
