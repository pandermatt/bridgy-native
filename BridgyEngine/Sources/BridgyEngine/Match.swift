/// Plays engines against each other, headlessly.
public enum Match {

    /// Plays one game to completion and returns the final position.
    ///
    /// If an engine fails to produce a legal move the game falls back to a
    /// random one, so a misbehaving engine loses on merit rather than hanging.
    public static func play(
        size: Int,
        blue: any Engine,
        red: any Engine,
        rng: inout SeededRandomNumberGenerator
    ) -> GameState {
        var state = GameState(size: size)
        while !state.isOver {
            let engine: any Engine = state.current == .blue ? blue : red
            let chosen = engine.chooseMove(in: state, rng: &rng)
            guard let move = chosen, state.isLegal(move) else {
                guard let fallback = state.legalMoves.randomElement(using: &rng) else { break }
                state.apply(fallback)
                continue
            }
            state.apply(move)
        }
        return state
    }

    /// Wins for `blue` across `games` games, alternating nothing — both engines
    /// keep their colours, because Bridg-It is not colour-symmetric.
    public static func winRate(
        size: Int,
        blue: any Engine,
        red: any Engine,
        games: Int,
        seed: UInt64 = 0x5EED
    ) -> Double {
        var rng = SeededRandomNumberGenerator(seed: seed)
        var blueWins = 0
        for _ in 0..<games where play(size: size, blue: blue, red: red, rng: &rng).winner == .blue {
            blueWins += 1
        }
        return Double(blueWins) / Double(games)
    }
}
