import Foundation
import Testing
@testable import BridgyEngine

/// Writes a mid-game position as JSON, for seeding a simulator:
///   BRIDGY_DUMP=/path/state.json swift test --filter StateDump
@Suite("State dump", .enabled(if: ProcessInfo.processInfo.environment["BRIDGY_DUMP"] != nil))
struct StateDump {
    @Test func dump() throws {
        var rng = SeededRandomNumberGenerator(seed: 5)
        var state = GameState(size: 5)
        let engine = GreedyEngine(strategy: .balanced)
        for _ in 0..<8 { state.apply(engine.chooseMove(in: state, rng: &rng)!) }
        let path = ProcessInfo.processInfo.environment["BRIDGY_DUMP"]!
        try JSONEncoder().encode(state).write(to: URL(fileURLWithPath: path))
    }
}
