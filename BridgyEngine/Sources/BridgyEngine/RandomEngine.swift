/// Picks uniformly among the empty cells.
///
/// Port of the original `RandomAlgorithm`.
public struct RandomEngine: Engine {
    public let identifier = "random"
    public let displayName = "Random"
    public let summary = "Plays anywhere at all. It has no plan and makes no attempt to connect or block."

    public init() {}

    public func chooseMove(in state: GameState, rng: inout SeededRandomNumberGenerator) -> Move? {
        state.legalMoves.randomElement(using: &rng)
    }
}
