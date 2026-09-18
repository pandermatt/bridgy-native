import Foundation
import Testing
@testable import BridgyEngine

/// Each engine against itself, so strength cannot explain a colour's win rate:
///   BRIDGY_FIRST=1 swift test --filter FirstPlayerProbe
@Suite("First-player probe", .enabled(if: ProcessInfo.processInfo.environment["BRIDGY_FIRST"] != nil))
struct FirstPlayerProbe {
    @Test func mirror() async {
        let games = Int(ProcessInfo.processInfo.environment["GAMES"] ?? "100")!
        for level in Difficulty.allCases {
            var line = level.displayName.padding(toLength: 8, withPad: " ", startingAt: 0)
            for size in [4, 6, 8, 10, 12, 14, 16] {
                let engine = level.tournamentEngine(forSize: size)
                // score(of: first, against: second) alternates colours; use a fixed-colour count instead.
                let rate = await downRate(engine, size: size, games: games)
                line += String(format: " %2d:%3.0f%%", size, rate * 100)
            }
            print(line)
        }
    }

    /// The whole field at each size, with Bradley–Terry separating strength
    /// from the value of moving first.
    @Test func controlled() async {
        let perColour = Int(ProcessInfo.processInfo.environment["PER_COLOUR"] ?? "10")!
        let participants = Tournament.defaultParticipants()
        for size in [4, 6, 8, 10, 12, 14] {
            let config = TournamentConfiguration(minimumSize: size, maximumSize: size, gamesPerColour: perColour)
            var games: [BradleyTerry.Game] = []
            for await o in Tournament.stream(configuration: config, participants: participants, seed: UInt64(size)) {
                games.append(.init(down: o.blue, across: o.red, downWon: o.winner == .blue))
            }
            let raw = Double(games.filter { $0.downWon }.count) / Double(games.count)
            let analysis = RatingAnalysis.run(games, participants: participants.count, resamples: 300)
            let ratings = zip(participants, analysis.fit.ratings).map { "\($0.name.prefix(4)) \(Int($1))" }.joined(separator: " ")
            FileHandle.standardError.write(Data(String(
                format: "size %2d  raw Down %.0f%%  controlled Down %.0f%% [%.0f–%.0f]  %@\n",
                size, raw * 100, analysis.fit.firstMoveWinRate * 100,
                analysis.firstMoveInterval.low * 100, analysis.firstMoveInterval.high * 100, ratings
            ).utf8))
        }
    }

    func downRate(_ engine: any Engine, size: Int, games: Int) async -> Double {
        await withTaskGroup(of: Int.self) { group in
            for i in 0..<games {
                group.addTask {
                    var rng = SeededRandomNumberGenerator(seed: SeededRandomNumberGenerator.mix(77, UInt64(i)))
                    return Match.play(size: size, blue: engine, red: engine, rng: &rng).winner == .blue ? 1 : 0
                }
            }
            var won = 0
            for await w in group { won += w }
            return Double(won) / Double(games)
        }
    }
}
