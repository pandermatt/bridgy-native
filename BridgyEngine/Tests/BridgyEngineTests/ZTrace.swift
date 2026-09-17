import Foundation
import Testing
@testable import BridgyEngine

@Suite("Trace", .enabled(if: ProcessInfo.processInfo.environment["BRIDGY_TRACE"] != nil))
struct Trace {
    @Test("Trace one game move by move")
    func trace() {
        let blue: any Engine = ShortestPathEngine(strategy: .balanced, tieBreak: .longestConnection)
        let red: any Engine = GreedyEngine(strategy: .balanced)
        var rng = SeededRandomNumberGenerator(seed: 99)
        var state = GameState(size: 4)
        while !state.isOver {
            let mover = state.current
            let engine: any Engine = mover == .blue ? blue : red
            let before = (ShortestPath.movesToWin(in: state, for: .blue),
                          ShortestPath.movesToWin(in: state, for: .red))
            guard let move = engine.chooseMove(in: state, rng: &rng) else { break }
            state.apply(move)
            let after = (ShortestPath.movesToWin(in: state, for: .blue),
                         ShortestPath.movesToWin(in: state, for: .red))
            print("\(mover) plays \(move)  blue:\(before.0.map(String.init) ?? "-")->\(after.0.map(String.init) ?? "-")  red:\(before.1.map(String.init) ?? "-")->\(after.1.map(String.init) ?? "-")")
        }
        print("winner: \(state.winner!)")
    }
}
