import Foundation
import Testing
@testable import BridgyEngine

@Suite("Ladder", .enabled(if: ProcessInfo.processInfo.environment["BRIDGY_LADDER"] != nil))
struct LadderDiagnostics {
    @Test("Measure the difficulty ladder")
    func ladder() {
        let size = 6
        let levels = Difficulty.allCases
        print("\nEach level as blue vs the level below, 12 games, size \(size)")
        for index in 1..<levels.count {
            let stronger = levels[index].engine(forSize: size)
            let weaker = levels[index - 1].engine(forSize: size)
            let asBlue = Match.winRate(size: size, blue: stronger, red: weaker, games: 12, seed: 5150)
            let asRed = 1 - Match.winRate(size: size, blue: weaker, red: stronger, games: 12, seed: 5151)
            print(String(format: "  %-8@ vs %-8@  blue %3.0f%%  red %3.0f%%",
                         levels[index].displayName as NSString,
                         levels[index - 1].displayName as NSString,
                         asBlue * 100, asRed * 100))
        }
        print("\nExpert vs Hard head to head, 12 games")
        let expert = Difficulty.expert.engine(forSize: size)
        let hard = Difficulty.hard.engine(forSize: size)
        print(String(format: "  expert as blue %3.0f%%   hard as blue %3.0f%%",
                     Match.winRate(size: size, blue: expert, red: hard, games: 12, seed: 61) * 100,
                     Match.winRate(size: size, blue: hard, red: expert, games: 12, seed: 62) * 100))
    }
}
