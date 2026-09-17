import Foundation
import Testing
@testable import BridgyEngine

@Suite("PerfectTrace", .enabled(if: ProcessInfo.processInfo.environment["BRIDGY_TRACE"] != nil))
struct PerfectTrace {
    @Test("Find the first move where the pairing gives up")
    func findBreak() {
        let perfect = PerfectEngine()
        let opponent: any Engine = ShortestPathEngine(strategy: .defensive, tieBreak: .random)
        var rng = SeededRandomNumberGenerator(seed: 1_964)
        for game in 0..<6 {
            var state = GameState(size: 6)
            var brokeAt: Int?
            while !state.isOver {
                if state.current == .blue {
                    if perfect.perfectMove(in: state) == nil, brokeAt == nil {
                        brokeAt = state.moveCount
                    }
                }
                let engine: any Engine = state.current == .blue ? perfect : opponent
                guard let move = engine.chooseMove(in: state, rng: &rng) else { break }
                state.apply(move)
            }
            print("game \(game): winner=\(state.winner!) moves=\(state.moveCount) pairingGaveUpAt=\(brokeAt.map(String.init) ?? "never")")
        }
    }
}
