/// An opponent that can choose a move.
///
/// Engines are pure values. They take the position and a generator and hand
/// back a move, so a whole match is reproducible from its seed. Long searches
/// honour `Task.isCancelled`, which is how the app abandons thinking when the
/// player restarts or leaves the board.
public protocol Engine: Sendable {
    /// Stable identifier, used for persistence and tournament reports.
    var identifier: String { get }
    /// Short name for the UI.
    var displayName: String { get }
    /// One or two sentences describing how it plays.
    var summary: String { get }

    func chooseMove(in state: GameState, rng: inout SeededRandomNumberGenerator) -> Move?
}

public extension Engine {
    /// Convenience for callers that do not care about reproducibility.
    func chooseMove(in state: GameState) -> Move? {
        var rng = SeededRandomNumberGenerator()
        return chooseMove(in: state, rng: &rng)
    }
}

/// How an engine balances its own connection against its opponent's.
///
/// Mirrors `StrategyTypes` in the original.
public enum Strategy: String, Sendable, Hashable, Codable, CaseIterable {
    /// Extend my own connection; ignore the opponent entirely.
    case aggressive
    /// Block the opponent's best move; ignore my own connection.
    case defensive
    /// Judge both and do whichever matters more.
    case balanced
}
