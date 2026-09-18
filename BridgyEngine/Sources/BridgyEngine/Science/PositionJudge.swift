/// Who is winning a position, for the win-chance chart.
///
/// Three sources, most certain first:
/// - a finished game is decided;
/// - if the side to move can force a win within two of its own moves, it is
///   winning outright — the puzzle solver proves it;
/// - otherwise a Monte Carlo search, which plays the position out a few
///   thousand times and reports how often the side to move's best reply won.
///
/// This replaced judging by a trained agent's network, which for anything but
/// a well-trained agent put every position near 50% and drew a flat line.
public enum PositionJudge {

    /// Down's chance of winning after `state`, between 0 and 1.
    public static func downChance(_ state: GameState) -> Double {
        if let winner = state.winner { return winner == .blue ? 1 : 0 }
        var solver = ForcedWinSolver()
        let moverChance: Double
        if solver.canForceWin(state, within: 2) {
            moverChance = 1
        } else {
            // Seeded by the position, so the same game always draws the same curve.
            var rng = SeededRandomNumberGenerator(seed: seed(for: state))
            let engine = MCTSEngine(iterations: playouts(forSize: state.board.size))
            // Search never quite proves a loss: keep it off the rails, which
            // are for the certainties above.
            moverChance = min(max(engine.evaluate(state, rng: &rng), 0.02), 0.98)
        }
        return state.current == .blue ? moverChance : 1 - moverChance
    }

    /// Down's chance after each of `counts` moves of a game, keyed by count.
    public static func history(moves: [Move], board: Board, counts: [Int]) -> [Int: Double] {
        var results: [Int: Double] = [:]
        var position = GameState(board: board)
        var played = 0
        for count in counts.sorted() {
            if Task.isCancelled { break }
            while played < count { position.apply(moves[played]); played += 1 }
            results[count] = downChance(position)
        }
        return results
    }

    /// The chances with the move-by-move wobble taken out.
    ///
    /// Random playouts slightly favour whoever just moved, so raw readings
    /// alternate up and down with every move — a sawtooth over the real
    /// curve. Weighting each reading ¼, ½, ¼ with its neighbours cancels any
    /// alternation exactly and leaves the trend. Certain readings (0 or 1)
    /// are left alone: they are proofs, not estimates.
    public static func smoothed(_ chances: [Int: Double]) -> [Int: Double] {
        var result = chances
        for (count, value) in chances where value > 0 && value < 1 {
            let before = chances[count - 1], after = chances[count + 1]
            switch (before, after) {
            case let (b?, a?): result[count] = 0.25 * b + 0.5 * value + 0.25 * a
            case let (b?, nil): result[count] = 0.5 * b + 0.5 * value
            case let (nil, a?): result[count] = 0.5 * value + 0.5 * a
            case (nil, nil): break
            }
        }
        return result
    }

    /// A move that swung the game: Down's chance before and after it.
    public struct TurningPoint: Hashable, Sendable {
        /// Counted from one: the move that was played.
        public let move: Int
        public let mover: Player
        public let before: Double
        public let after: Double

        /// How much the mover gained (positive) or threw away (negative).
        public var swingForMover: Double {
            mover == .blue ? after - before : before - after
        }
    }

    /// The moves that changed the game most, biggest first: any that moved
    /// the chance by at least `threshold`, at most `limit` of them.
    public static func turningPoints(in chances: [Int: Double], threshold: Double = 0.2, limit: Int = 3) -> [TurningPoint] {
        chances.keys.sorted().compactMap { count -> TurningPoint? in
            guard count > 0, let before = chances[count - 1], let after = chances[count] else { return nil }
            // Move `count` was played by Down when count is odd: Down moves first.
            let mover: Player = count % 2 == 1 ? .blue : .red
            let point = TurningPoint(move: count, mover: mover, before: before, after: after)
            return abs(after - before) >= threshold ? point : nil
        }
        .sorted { abs($0.after - $0.before) > abs($1.after - $1.before) }
        .prefix(limit)
        .sorted { $0.move < $1.move }
    }

    /// Enough playouts for a steady reading, fewer on big boards where each
    /// playout costs more.
    static func playouts(forSize size: Int) -> Int {
        switch size {
        case ..<5: 1_500
        case ..<8: 2_500
        case ..<12: 1_500
        default: 800
        }
    }

    private static func seed(for state: GameState) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for move in state.moves {
            hash = (hash ^ UInt64(state.board.index(of: move))) &* 0x100_0000_01b3
        }
        return hash ^ UInt64(state.board.size)
    }
}
