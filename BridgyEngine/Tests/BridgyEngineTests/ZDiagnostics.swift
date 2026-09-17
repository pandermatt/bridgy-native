import Foundation
import Testing
@testable import BridgyEngine

/// Not part of the normal run. Set BRIDGY_DIAGNOSTICS=1 to print strength tables.
@Suite(
    "Diagnostics",
    .enabled(if: ProcessInfo.processInfo.environment["BRIDGY_DIAGNOSTICS"] != nil)
)
struct Diagnostics {
    @Test("Print the head-to-head matrix")
    func matrix() {
        let engines: [(String, any Engine)] = [
            ("random    ", RandomEngine()),
            ("greedy-agg", GreedyEngine(strategy: .aggressive)),
            ("greedy-bal", GreedyEngine(strategy: .balanced)),
            ("path-avoid", ShortestPathEngine(strategy: .balanced, tieBreak: .avoidConnection)),
            ("path-long ", ShortestPathEngine(strategy: .balanced, tieBreak: .longestConnection)),
            ("path-dist ", ShortestPathEngine(strategy: .balanced, tieBreak: .disturbOpponent)),
            ("path-rand ", ShortestPathEngine(strategy: .balanced, tieBreak: .random))
        ]
        print("\nblue-win% at size 6, 40 games (row = blue, column = red)")
        print("            " + engines.map { $0.0 }.joined(separator: " "))
        for (blueName, blue) in engines {
            var row = blueName + "  "
            for (_, red) in engines {
                let rate = Match.winRate(size: 6, blue: blue, red: red, games: 40, seed: 99)
                row += String(format: "%9.0f%% ", rate * 100)
            }
            print(row)
        }
    }
}
