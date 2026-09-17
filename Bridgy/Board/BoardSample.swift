import BridgyEngine

/// A fixed position to show a style against.
///
/// Replayed from the seeded engines rather than a hand-written list of moves, so
/// it cannot drift out of step with the board's own indexing, and so it looks
/// like a real game rather than an arrangement.
enum BoardSample {
    static let midGame: GameState = {
        var state = GameState(size: 5)
        var rng = SeededRandomNumberGenerator(seed: 42)
        let blue = ShortestPathEngine(strategy: .balanced)
        let red = GreedyEngine(strategy: .balanced)
        // Enough to show bridges meeting and turning, well short of a result.
        for _ in 0..<16 {
            guard !state.isOver else { break }
            let engine: any Engine = state.current == .blue ? blue : red
            guard let move = engine.chooseMove(in: state, rng: &rng) else { break }
            state.apply(move)
        }
        return state
    }()
}
