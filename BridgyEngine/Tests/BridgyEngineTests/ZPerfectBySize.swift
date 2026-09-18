import Foundation
import Testing
@testable import BridgyEngine

/// Settles "Perfect isn't perfect above 10 — or is it odd sizes?" with data.
@Suite("Perfect by colour", .enabled(if: ProcessInfo.processInfo.environment["BRIDGY_PERFECT"] != nil))
struct PerfectByColour {
    @Test func bySizeAndColour() {
        print("\nPerfect against every tournament engine, 4 games each side, by size")
        for size in 2...12 {
            let perfect = Difficulty.perfect.tournamentEngine(forSize: size)
            var asDown = (won: 0, played: 0)
            var asAcross = (won: 0, played: 0)
            for (index, level) in Difficulty.allCases.enumerated() where level != .perfect {
                let other = level.tournamentEngine(forSize: size)
                for game in 0..<4 {
                    var rng = SeededRandomNumberGenerator(seed: SeededRandomNumberGenerator.mix(UInt64(size), UInt64(index * 10 + game)))
                    let a = Match.play(size: size, blue: perfect, red: other, rng: &rng)
                    asDown.played += 1; if a.winner == .blue { asDown.won += 1 }
                    let b = Match.play(size: size, blue: other, red: perfect, rng: &rng)
                    asAcross.played += 1; if b.winner == .red { asAcross.won += 1 }
                }
            }
            print(String(format: "  %2d×%-2d  as Down %2d/%-2d   as Across %2d/%-2d",
                         size, size, asDown.won, asDown.played, asAcross.won, asAcross.played))
        }
    }
}
