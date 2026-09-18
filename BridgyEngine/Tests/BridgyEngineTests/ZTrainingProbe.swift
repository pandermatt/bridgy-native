import Foundation
import Testing
@testable import BridgyEngine
@testable import BridgyTraining

/// Trains with the default parameters and prints how it fares, round by round:
///   BRIDGY_PROBE=1 SIZE=5 ROUNDS=30 swift test --filter TrainingProbe
@Suite("Training probe", .enabled(if: ProcessInfo.processInfo.environment["BRIDGY_PROBE"] != nil))
struct TrainingProbe {
    @Test func probe() async throws {
        var p = TrainingParameters()
        let env = ProcessInfo.processInfo.environment
        p.boardSize = Int(env["SIZE"] ?? "5")!
        p.rounds = Int(env["ROUNDS"] ?? "30")!
        if let v = env["STEPS"] { p.stepsPerRound = Int(v)! }
        if let v = env["LR"] { p.learningRate = Double(v)! }
        if let v = env["GAMES"] { p.gamesPerRound = Int(v)! }
        if let v = env["SIMS"] { p.simulations = Int(v)! }
        if let v = env["BLOCKS"] { p.blocks = Int(v)! }
        let clock = ContinuousClock(); let t0 = clock.now
        var last: NetworkWeights?
        var loss = (Float(0), Float(0))
        for await e in Training.run(parameters: p) {
            switch e {
            case .loss(_, let a, let b): loss = (a, b)
            case .gate(let r, let s, let acc): print("r\(r) \(clock.now - t0) loss p=\(loss.0) v=\(loss.1) gate \(s) \(acc)")
            case .benchmark(let r, let o, let s): print("   r\(r) vs \(o) \(s)")
            case .checkpoint(_, _, let w): last = w
            default: break
            }
        }
        let w = try #require(last)
        if let out = env["OUT"] { try w.data().write(to: URL(fileURLWithPath: out)) }
        for sims in [48, 200] {
            for level in [Difficulty.medium, .hard, .expert, .perfect] {
                let s = await Arena.score(of: NeuralMCTSEngine(network: NeuralNetwork(weights: w), simulations: sims), against: level.tournamentEngine(forSize: p.boardSize), size: p.boardSize, games: 40, seed: 99)
                print("final sims=\(sims) vs \(level.displayName): \(s)")
            }
        }
    }
}
