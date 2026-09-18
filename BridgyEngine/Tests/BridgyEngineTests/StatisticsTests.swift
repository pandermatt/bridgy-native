import Foundation
import Testing
@testable import BridgyEngine

@Suite("Statistics")
struct StatisticsTests {

    private func isClose(_ a: Double, _ b: Double, tolerance: Double = 0.001) -> Bool {
        abs(a - b) <= tolerance
    }

    @Test("Wilson interval matches published values")
    func wilsonKnownValues() {
        // 50/100 at 95% is the textbook example: [0.4038, 0.5962].
        let even = Statistics.wilsonInterval(wins: 50, total: 100)
        #expect(isClose(even.low, 0.4038))
        #expect(isClose(even.high, 0.5962))

        // 1/1 is where the normal approximation gives the nonsense "100% ± 0".
        let single = Statistics.wilsonInterval(wins: 1, total: 1)
        #expect(isClose(single.low, 0.2065))
        #expect(isClose(single.high, 1.0))

        // 0/10 must not dip below zero.
        let none = Statistics.wilsonInterval(wins: 0, total: 10)
        #expect(none.low == 0)
        #expect(isClose(none.high, 0.2775, tolerance: 0.005))
    }

    @Test("Wilson interval stays inside zero and one", arguments: [0, 1, 2, 5, 13, 100])
    func wilsonStaysInBounds(total: Int) {
        for wins in 0...max(total, 0) {
            let interval = Statistics.wilsonInterval(wins: wins, total: total)
            #expect(interval.low >= 0)
            #expect(interval.high <= 1)
            #expect(interval.low <= interval.high)
        }
    }

    @Test("An empty sample admits everything")
    func wilsonWithNoGames() {
        let interval = Statistics.wilsonInterval(wins: 0, total: 0)
        #expect(interval.low == 0)
        #expect(interval.high == 1)
    }

    @Test("More evidence narrows the interval")
    func wilsonNarrows() {
        var previous = Double.infinity
        for exponent in 1...5 {
            let total = Int(pow(10.0, Double(exponent)))
            let width = Statistics.wilsonInterval(wins: total / 2, total: total).width
            #expect(width < previous, "width did not shrink at n = \(total)")
            previous = width
        }
    }

    @Test("Evenly matched players split the adjustment")
    func eloFirstGame() {
        var elo = EloRating(count: 2, kFactor: 24)
        #expect(elo.expectedScore(0, against: 1) == 0.5)
        elo.record(winner: 0, loser: 1)
        // Expected 0.5, so the winner takes half of K.
        #expect(isClose(elo[0], 1512))
        #expect(isClose(elo[1], 1488))
    }

    @Test("Elo is zero-sum")
    func eloConserved() {
        var elo = EloRating(count: 4)
        var rng = SeededRandomNumberGenerator(seed: 99)
        for _ in 0..<200 {
            let a = Int.random(in: 0..<4, using: &rng)
            var b = Int.random(in: 0..<4, using: &rng)
            if a == b { b = (b + 1) % 4 }
            elo.record(winner: a, loser: b)
        }
        let total = elo.ratings.reduce(0, +)
        #expect(isClose(total, 4 * EloRating.initialRating, tolerance: 0.01))
    }

    @Test("A consistent winner ends up rated highest")
    func eloRanksConsistentWinner() {
        var elo = EloRating(count: 3)
        for _ in 0..<50 {
            elo.record(winner: 0, loser: 1)
            elo.record(winner: 0, loser: 2)
            elo.record(winner: 1, loser: 2)
        }
        #expect(elo[0] > elo[1])
        #expect(elo[1] > elo[2])
    }

    @Test("Beating a weaker opponent moves the rating less than beating a stronger one")
    func eloRewardsUpsets() {
        var lopsided = EloRating(count: 2)
        for _ in 0..<30 { lopsided.record(winner: 0, loser: 1) }

        var favourite = lopsided
        favourite.record(winner: 0, loser: 1)
        let expectedGain = favourite[0] - lopsided[0]

        var underdog = lopsided
        underdog.record(winner: 1, loser: 0)
        let upsetGain = underdog[1] - lopsided[1]

        #expect(upsetGain > expectedGain)
    }
}

@Suite("Tournament streaming")
struct TournamentStreamTests {

    @Test("The stream emits exactly the advertised number of games")
    func emitsEveryGame() async {
        let configuration = TournamentConfiguration(minimumSize: 3, maximumSize: 4, gamesPerColour: 1)
        let participants = [
            Participant(name: "Random", engine: RandomEngine()),
            Participant(name: "Greedy", engine: GreedyEngine(strategy: .balanced)),
            Participant(name: "Path", engine: ShortestPathEngine())
        ]
        var count = 0
        for await _ in Tournament.stream(configuration: configuration, participants: participants) {
            count += 1
        }
        #expect(count == configuration.totalGames(participants: participants.count))
    }

    @Test("Analysis folds the stream into consistent totals")
    func analysisIsConsistent() async {
        let configuration = TournamentConfiguration(minimumSize: 3, maximumSize: 4, gamesPerColour: 1)
        let participants = [
            Participant(name: "Random", engine: RandomEngine()),
            Participant(name: "Greedy", engine: GreedyEngine(strategy: .balanced)),
            Participant(name: "Path", engine: ShortestPathEngine())
        ]
        var analysis = TournamentAnalysis(
            participants: participants.map(\.name),
            configuration: configuration
        )
        for await outcome in Tournament.stream(configuration: configuration, participants: participants) {
            analysis.record(outcome)
        }
        analysis.finish()

        let total = configuration.totalGames(participants: participants.count)
        #expect(analysis.gamesPlayed == total)

        // Every game contributes one win and two participations.
        let records = analysis.overall
        #expect(records.reduce(0) { $0 + $1.wins } == total)
        #expect(records.reduce(0) { $0 + $1.games } == total * 2)

        // Blue's tally across sizes must also account for every game.
        let blue = configuration.sizes.reduce(0) { $0 + analysis.firstPlayerRecord(atSize: $1).games }
        #expect(blue == total)

        // Ratings stay zero-sum, and every engine has a sampled history.
        #expect(abs(analysis.elo.ratings.reduce(0, +) - 3 * EloRating.initialRating) < 0.01)
        #expect(Set(analysis.eloHistory.map(\.participant)).count == participants.count)
    }

    @Test("Cancelling stops the run")
    func cancellationStops() async {
        let configuration = TournamentConfiguration(minimumSize: 4, maximumSize: 8, gamesPerColour: 20)
        let participants = Tournament.defaultParticipants(forSize: 8)
        var count = 0
        for await _ in Tournament.stream(configuration: configuration, participants: participants) {
            count += 1
            if count == 5 { break }
        }
        #expect(count == 5)
        #expect(count < configuration.totalGames(participants: participants.count))
    }
}

@Suite("Parallel tournament")
struct ParallelTournamentTests {
    private func collect(parallelism: Int) async -> [Tournament.Outcome] {
        let configuration = TournamentConfiguration(minimumSize: 3, maximumSize: 5, gamesPerColour: 2)
        var outcomes: [Tournament.Outcome] = []
        for await outcome in Tournament.stream(
            configuration: configuration,
            participants: [
                Participant(name: "Random", engine: RandomEngine()),
                Participant(name: "Greedy", engine: GreedyEngine(strategy: .balanced)),
                Participant(name: "Path", engine: ShortestPathEngine())
            ],
            seed: 42,
            parallelism: parallelism
        ) { outcomes.append(outcome) }
        return outcomes
    }

    /// Running on many cores must not change a single result, or the order
    /// they arrive in — Elo history depends on that order.
    @Test("Many cores give exactly the results one core gives, in the same order")
    func parallelMatchesSerial() async {
        let serial = await collect(parallelism: 1)
        let parallel = await collect(parallelism: 8)
        #expect(!serial.isEmpty)
        #expect(serial == parallel)
        #expect(parallel.map(\.gameIndex) == Array(0..<parallel.count))
    }
}

@Suite("Results by colour")
struct ColourSplitTests {
    /// The split has to add back up to the combined figure, and Perfect's Down
    /// column has to be spotless — that is the whole reason the split exists.
    @Test("Down and Across add up to the total, and Perfect never loses as Down")
    func splitIsConsistent() async {
        let configuration = TournamentConfiguration(minimumSize: 3, maximumSize: 6, gamesPerColour: 2)
        let participants = Tournament.defaultParticipants()
        var analysis = TournamentAnalysis(participants: participants.map(\.name), configuration: configuration)
        for await outcome in Tournament.stream(configuration: configuration, participants: participants) {
            analysis.record(outcome)
        }
        for index in participants.indices {
            for size in configuration.sizes {
                let both = analysis.record(of: index, atSize: size)
                let down = analysis.record(of: index, atSize: size, as: .blue)
                let across = analysis.record(of: index, atSize: size, as: .red)
                #expect(down.wins + across.wins == both.wins)
                #expect(down.games + across.games == both.games)
            }
        }
        let perfect = try! #require(participants.firstIndex { $0.name == Difficulty.perfect.displayName })
        let asDown = analysis.record(of: perfect, as: .blue)
        #expect(asDown.games > 0)
        #expect(asDown.wins == asDown.games, "Perfect lost \(asDown.games - asDown.wins) games as Down")
    }
}
