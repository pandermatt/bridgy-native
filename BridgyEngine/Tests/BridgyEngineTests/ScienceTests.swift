import Foundation
import Testing
@testable import BridgyEngine

@Suite("Bradley–Terry")
struct BradleyTerryTests {

    /// Games drawn from a known model, every pairing in both colours.
    static func synthetic(strengths: [Double], firstMove: Double, gamesPerPairing: Int, seed: UInt64) -> [BradleyTerry.Game] {
        var rng = SeededRandomNumberGenerator(seed: seed)
        var games: [BradleyTerry.Game] = []
        for i in strengths.indices {
            for j in strengths.indices where i != j {
                let p = BradleyTerry.sigmoid(strengths[i] - strengths[j] + firstMove)
                for _ in 0..<gamesPerPairing {
                    games.append(.init(down: i, across: j, downWon: Double.random(in: 0..<1, using: &rng) < p))
                }
            }
        }
        return games
    }

    @Test("Recovers known strengths and a known first-move effect")
    func recovers() {
        let truth = [-1.0, -0.2, 0.3, 0.9]
        let games = Self.synthetic(strengths: truth, firstMove: 0.4, gamesPerPairing: 400, seed: 1)
        let fit = BradleyTerry.fit(games, participants: 4, ridge: 0.0001)
        let centred = truth.map { $0 - truth.reduce(0, +) / 4 }
        for (estimate, actual) in zip(fit.strengths, centred) {
            #expect(abs(estimate - actual) < 0.1, "\(estimate) vs \(actual)")
        }
        #expect(abs(fit.firstMove - 0.4) < 0.08)
    }

    @Test("Sees through a schedule that makes the raw first-player rate lie")
    func confounding() {
        // A strong engine always plays Across against a weak one: raw Down rate
        // is low, yet moving first is an advantage.
        var rng = SeededRandomNumberGenerator(seed: 3)
        var games: [BradleyTerry.Game] = []
        let strong = 2.0, weak = 0.0, first = 0.5
        for _ in 0..<600 {
            let p = BradleyTerry.sigmoid(weak - strong + first)
            games.append(.init(down: 0, across: 1, downWon: Double.random(in: 0..<1, using: &rng) < p))
        }
        for _ in 0..<200 {
            let p = BradleyTerry.sigmoid(strong - weak + first)
            games.append(.init(down: 1, across: 0, downWon: Double.random(in: 0..<1, using: &rng) < p))
        }
        let raw = Double(games.filter(\.downWon).count) / Double(games.count)
        let fit = BradleyTerry.fit(games, participants: 2, ridge: 0.0001)
        #expect(raw < 0.5)
        #expect(fit.firstMoveWinRate > 0.55)
    }

    @Test("Stays finite when an engine never loses")
    func separation() {
        let games = (0..<50).map { _ in BradleyTerry.Game(down: 0, across: 1, downWon: true) }
        let fit = BradleyTerry.fit(games, participants: 2)
        #expect(fit.strengths.allSatisfy { $0.isFinite })
        #expect(fit.firstMove.isFinite)
    }

    @Test("Bootstrap intervals are reproducible and contain the estimate")
    func bootstrap() {
        let games = Self.synthetic(strengths: [0, 0.5, 1], firstMove: 0.3, gamesPerPairing: 60, seed: 9)
        let a = RatingAnalysis.run(games, participants: 3, resamples: 100, seed: 5)
        let b = RatingAnalysis.run(games, participants: 3, resamples: 100, seed: 5)
        #expect(a == b)
        for (rating, interval) in zip(a.fit.ratings, a.ratingIntervals) {
            #expect(interval.low <= rating && rating <= interval.high)
        }
        #expect(a.firstMoveInterval.low < a.fit.firstMoveWinRate && a.fit.firstMoveWinRate < a.firstMoveInterval.high)
    }
}

@Suite("Significance")
struct SignificanceTests {

    @Test("Exact binomial p-values match known values")
    func binomial() {
        #expect(abs(Significance.binomialPValue(wins: 9, games: 10) - 0.021484375) < 1e-9)
        #expect(abs(Significance.binomialPValue(wins: 5, games: 10) - 1) < 1e-9)
        #expect(abs(Significance.binomialPValue(wins: 0, games: 5) - 0.0625) < 1e-9)
    }

    @Test("Holm adjusts in step-down order")
    func holm() {
        let adjusted = Significance.holm([0.01, 0.04, 0.03, 0.005])
        #expect(adjusted.map { ($0 * 1000).rounded() / 1000 } == [0.03, 0.06, 0.06, 0.02])
    }

    @Test("Sample-size guidance is the textbook figure")
    func sampleSize() {
        #expect(Significance.gamesNeeded(halfWidth: 0.05) == 385)
    }

    @Test("SPRT keeps its false-positive rate near alpha")
    func sprt() {
        var rng = SeededRandomNumberGenerator(seed: 11)
        var falsePositives = 0
        var totalGames = 0
        let trials = 2_000
        for _ in 0..<trials {
            var test = SequentialTest(p0: 0.5, p1: 0.6, alpha: 0.05, beta: 0.05)
            while test.decision == .undecided {
                test.record(win: Double.random(in: 0..<1, using: &rng) < 0.5)
            }
            if test.decision == .acceptH1 { falsePositives += 1 }
            totalGames += test.games
        }
        let rate = Double(falsePositives) / Double(trials)
        #expect(rate < 0.07, "False positives \(rate)")
        // And it decides in far fewer games than a fixed test of the same power (~ 270).
        #expect(Double(totalGames) / Double(trials) < 200)
    }
}
