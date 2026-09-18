import Foundation
import Testing
@testable import BridgyEngine

@Suite("Timing", .enabled(if: ProcessInfo.processInfo.environment["BRIDGY_TIMING"] != nil))
struct TimingDiagnostics {
    private func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    /// The claim "random vs random should be instant", measured.
    @Test("Time random against random")
    func randomCost() {
        let clock = ContinuousClock()
        print("\nrandom vs random, 20 games each")
        for size in [6, 12, 35] {
            var rng = SeededRandomNumberGenerator(seed: 1)
            var moves = 0
            let elapsed = clock.measure {
                for _ in 0..<20 {
                    moves += Match.play(size: size, blue: RandomEngine(), red: RandomEngine(), rng: &rng).moveCount
                }
            }
            print(String(format: "  size %2d: %8.2f ms per game, %6.2f µs per move",
                         size, ms(elapsed) / 20, ms(elapsed) * 1000 / Double(max(moves, 1))))
        }
    }

    /// The app's default tournament, end to end.
    @Test("Time the default tournament")
    func tournamentCost() async {
        let configuration = TournamentConfiguration(minimumSize: 4, maximumSize: 6, gamesPerColour: 3)
        let clock = ContinuousClock()
        var games = 0
        let elapsed = await clock.measure {
            for await _ in Tournament.stream(
                configuration: configuration,
                participants: Tournament.defaultParticipants(forSize: 6)
            ) { games += 1 }
        }
        print(String(format: "\ndefault tournament: %d games in %.0f ms", games, ms(elapsed)))
    }

    @Test("Time a full Perfect game at several sizes")
    func perfectCost() {
        let clock = ContinuousClock()
        print("\nfull Perfect-vs-Greedy game, blue = Perfect")
        for size in [6, 8, 10, 12, 16] {
            var rng = SeededRandomNumberGenerator(seed: 5)
            let blue = PerfectEngine(fallback: ShortestPathEngine())
            let red = GreedyEngine(strategy: .balanced)
            var moves = 0
            let elapsed = clock.measure {
                let final = Match.play(size: size, blue: blue, red: red, rng: &rng)
                moves = final.moveCount
            }
            let ms = Double(elapsed.components.seconds) * 1000
                + Double(elapsed.components.attoseconds) / 1e15
            print(String(format: "  size %2d: %7.1f ms total, %2d moves, %6.2f ms/move",
                         size, ms, moves, ms / Double(max(moves, 1))))
        }
    }

    /// The path the engine used before the cache: rebuild the pairing and replay
    /// the whole history, every call.
    private func replayReply(board: Board, history: [Move]) -> Move? {
        if history.isEmpty { return PairingStrategy.opening }
        guard history[0] == PairingStrategy.opening else { return nil }
        guard var pairing = PairingStrategy(board: board) else { return nil }
        var index = 1
        var reply: Move?
        while index < history.count {
            guard let answer = pairing.respond(to: board.index(of: history[index])) else { return nil }
            let answerMove = board.move(at: answer)
            if index + 1 < history.count {
                guard history[index + 1] == answerMove else { return nil }
            } else {
                reply = answerMove
            }
            index += 2
        }
        return reply
    }

    @Test("Compare the cache against rebuilding every move")
    func cachedVersusReplay() {
        let clock = ContinuousClock()
        print("\nsame games, cached pairing vs rebuild-every-move")
        for size in [6, 8, 10, 12] {
            var rng = SeededRandomNumberGenerator(seed: 11)
            var state = GameState(size: size)
            let cache = PairingCache()

            let cachedTime = clock.measure {
                while !state.isOver {
                    if state.current == .blue {
                        let move = state.moves.isEmpty
                            ? PairingStrategy.opening
                            : cache.reply(board: state.board, history: state.moves)
                        guard let move else { break }
                        state.apply(move)
                    } else if let move = state.legalMoves.randomElement(using: &rng) {
                        state.apply(move)
                    }
                }
            }
            let history = state.moves

            // Replay the same finished game, deriving each blue move from scratch.
            let replayTime = clock.measure {
                var prefix: [Move] = []
                for (index, move) in history.enumerated() {
                    if index.isMultiple(of: 2) { _ = replayReply(board: state.board, history: prefix) }
                    prefix.append(move)
                }
            }

            func ms(_ d: Duration) -> Double {
                Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
            }
            print(String(format: "  size %2d: cached %7.1f ms, rebuilt %8.1f ms  (%.0fx)",
                         size, ms(cachedTime), ms(replayTime),
                         ms(replayTime) / max(ms(cachedTime), 0.001)))
        }
    }
}
