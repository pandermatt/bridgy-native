import Testing
@testable import BridgyEngine

@Suite("Game records")
struct GameRecordTests {

    @Test("Every recorded game replays to the same winner")
    func replays() async {
        let config = TournamentConfiguration(minimumSize: 3, maximumSize: 5, gamesPerColour: 2)
        let participants = Tournament.defaultParticipants(forSize: 5).prefix(4).map { $0 }
        var count = 0
        for await outcome in Tournament.stream(configuration: config, participants: participants) {
            var state = GameState(size: outcome.size)
            for cell in outcome.moves {
                let applied = state.apply(state.board.move(at: Int(cell)))
                #expect(applied)
            }
            #expect(state.winner == outcome.winner)
            #expect(state.isOver)
            count += 1
        }
        #expect(count == config.totalGames(participants: participants.count))
    }

    @Test("Mirror schedules put each participant on both sides of its own games")
    func mirror() {
        let jobs = Tournament.mirrorJobs(sizes: [4, 6], participants: 3, gamesPerSize: 5, seed: 1)
        #expect(jobs.count == 30)
        #expect(jobs.allSatisfy { $0.blue == $0.red })
        #expect(Set(jobs.map(\.seed)).count == jobs.count)
    }

    @Test("Match schedules pin a colour when asked")
    func match() {
        let pinned = Tournament.matchJobs(first: 0, second: 1, size: 5, firstPlays: .red, games: 10, seed: 2)
        #expect(pinned.allSatisfy { $0.red == 0 && $0.blue == 1 })
        let alternating = Tournament.matchJobs(first: 0, second: 1, size: 5, firstPlays: nil, games: 10, seed: 2)
        #expect(alternating.filter { $0.blue == 0 }.count == 5)
    }
}
