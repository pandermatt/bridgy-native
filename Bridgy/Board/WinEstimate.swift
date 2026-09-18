import BridgyEngine
import Foundation

/// Down's chance of winning, as a trained agent's network judges a position.
///
/// The inspector offers this beside the default judge, `PositionJudge`.
enum WinEstimate {

    /// Down's chance in one position: certain once the game is decided,
    /// otherwise the network's value, turned from the mover's side to Down's.
    static func downChance(_ state: GameState, network: NeuralNetwork) -> Double {
        if let winner = state.winner { return winner == .blue ? 1 : 0 }
        let mover = (Double(network.judge(state).value) + 1) / 2
        return state.current == .blue ? mover : 1 - mover
    }

    /// Down's chance after each of `counts` moves of a game, keyed by count.
    static func history(moves: [Move], board: Board, counts: [Int], network: NeuralNetwork) -> [Int: Double] {
        var results: [Int: Double] = [:]
        var position = GameState(board: board)
        var played = 0
        for count in counts.sorted() {
            if Task.isCancelled { break }
            while played < count { position.apply(moves[played]); played += 1 }
            results[count] = downChance(position, network: network)
        }
        return results
    }
}
