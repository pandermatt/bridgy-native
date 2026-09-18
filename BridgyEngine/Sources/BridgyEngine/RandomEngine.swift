/// Picks uniformly among the empty cells.
///
/// Port of the original `RandomAlgorithm`.
public struct RandomEngine: Engine {
    public let identifier = "random"
    public let displayName = "Random"
    public let summary = "Plays anywhere at all. It has no plan and makes no attempt to connect or block."

    public init() {}

    /// Guesses a cell and keeps it if it is empty; once the board is mostly
    /// full, counts along to a randomly chosen empty cell instead.
    ///
    /// Building the list of legal moves every turn scans and allocates every
    /// cell, which made a whole 35×35 game cost the square of the cell count —
    /// over half a second for a player that is meant to be instant. While at
    /// least a quarter of the board is free, a few guesses find an empty cell.
    public func chooseMove(in state: GameState, rng: inout SeededRandomNumberGenerator) -> Move? {
        guard !state.isOver else { return nil }
        let count = state.board.cellCount
        let free = count - state.moveCount
        guard free > 0 else { return nil }
        if free * 4 >= count {
            while true {
                let cell = Int.random(in: 0..<count, using: &rng)
                if state.cells[cell] == nil { return state.board.move(at: cell) }
            }
        }
        // Mostly full: pick the k-th empty cell in one pass, without building a
        // list of every legal move — that list alone cost ~250 µs at 35×35.
        var remaining = Int.random(in: 0..<free, using: &rng)
        for cell in 0..<count where state.cells[cell] == nil {
            if remaining == 0 { return state.board.move(at: cell) }
            remaining -= 1
        }
        return nil
    }
}
