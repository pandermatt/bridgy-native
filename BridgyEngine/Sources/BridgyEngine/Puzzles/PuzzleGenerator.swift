/// A position with a forced win for the side to move.
public struct Puzzle: Sendable, Hashable, Codable {
    public let state: GameState
    /// How many of its own moves the side to move needs, at best.
    public let movesToWin: Int
    public let seed: UInt64

    public var solver: Player { state.current }
}

/// Finds puzzles: positions from real-looking games where the side to move
/// can force a win in exactly `n` moves — and not fewer, so the count is true.
public enum PuzzleGenerator {

    public static func make(size: Int, movesToWin: ClosedRange<Int> = 2...3, seed: UInt64) -> Puzzle? {
        var rng = SeededRandomNumberGenerator(seed: seed)
        let player = GreedyEngine(strategy: .balanced)
        for attempt in 0..<40 {
            var state = GameState(size: size)
            // A few random opening moves so games differ, then sensible play.
            let opening = Int.random(in: 1...max(1, size), using: &rng)
            var history: [GameState] = []
            while !state.isOver {
                history.append(state)
                let move = state.moveCount < opening
                    ? state.legalMoves.randomElement(using: &rng)
                    : player.chooseMove(in: state, rng: &rng)
                guard let move else { break }
                state.apply(move)
            }
            // Walk back from the end: the first position with a forced win
            // of the wanted length, that isn't already a win in one.
            var solver = ForcedWinSolver()
            for position in history.reversed() {
                guard let distance = ShortestPath.movesToWin(in: position, for: position.current),
                      distance >= 2, distance <= movesToWin.upperBound else { continue }
                guard let n = solver.shortestForcedWin(position, limit: movesToWin.upperBound),
                      movesToWin.contains(n) else { continue }
                return Puzzle(state: position, movesToWin: n, seed: SeededRandomNumberGenerator.mix(seed, UInt64(attempt)))
            }
        }
        return nil
    }
}
