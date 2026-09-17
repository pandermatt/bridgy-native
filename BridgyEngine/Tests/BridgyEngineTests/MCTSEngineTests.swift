import Testing
@testable import BridgyEngine

@Suite("Monte Carlo search")
struct MCTSEngineTests {

    private func engine(_ iterations: Int = 1_500) -> MCTSEngine {
        MCTSEngine(iterations: iterations)
    }

    @Test("A random completion always produces a winner", arguments: 2...10)
    func playoutsDecide(size: Int) {
        var rng = SeededRandomNumberGenerator(seed: UInt64(size) &* 13)
        let state = GameState(size: size)
        for _ in 0..<50 {
            let result = Playout.run(from: state, rng: &rng)
            #expect(result.blueCells.count + result.redCells.count == state.board.cellCount)
            #expect(result.blueCells.isDisjoint(with: result.redCells))
            // Blue moves first on an odd number of cells, so it always gets one more.
            #expect(result.blueCells.count == result.redCells.count + 1)
        }
    }

    @Test("A playout of a decided position keeps that result")
    func playoutRespectsFinishedGames() {
        var state = GameState(size: 3)
        for move in [
            Move(kind: .v, row: 0, col: 0), Move(kind: .v, row: 0, col: 2),
            Move(kind: .v, row: 1, col: 0), Move(kind: .v, row: 1, col: 2),
            Move(kind: .v, row: 2, col: 0)
        ] {
            state.apply(move)
        }
        #expect(state.winner == .blue)
        var rng = SeededRandomNumberGenerator(seed: 8)
        #expect(Playout.run(from: state, rng: &rng).winner == .blue)
    }

    @Test("Search only returns legal moves", arguments: [2, 4, 6])
    func movesAreLegal(size: Int) {
        var rng = SeededRandomNumberGenerator(seed: 606)
        var state = GameState(size: size)
        let mcts = engine(300)
        while !state.isOver {
            let engineToPlay: any Engine = state.current == .blue ? mcts : RandomEngine()
            guard let move = engineToPlay.chooseMove(in: state, rng: &rng) else { break }
            #expect(state.isLegal(move))
            state.apply(move)
        }
        #expect(state.winner != nil)
    }

    @Test("Search takes a win and refuses to walk into a loss")
    func handlesDecisiveMoves() {
        var state = GameState(size: 3)
        for move in [
            Move(kind: .v, row: 0, col: 0), Move(kind: .v, row: 0, col: 2),
            Move(kind: .v, row: 1, col: 0), Move(kind: .v, row: 1, col: 2)
        ] {
            state.apply(move)
        }
        var rng = SeededRandomNumberGenerator(seed: 3)
        #expect(engine().chooseMove(in: state, rng: &rng) == Move(kind: .v, row: 2, col: 0))

        // Same position with red to move: it has to block.
        var blocking = state
        blocking.apply(Move(kind: .h, row: 1, col: 1))
        #expect(blocking.current == .red)
        var rng2 = SeededRandomNumberGenerator(seed: 3)
        #expect(engine().chooseMove(in: blocking, rng: &rng2) == Move(kind: .v, row: 2, col: 0))
    }

    @Test("A fixed iteration budget plays the same game twice")
    func isReproducible() {
        var first = SeededRandomNumberGenerator(seed: 2024)
        var second = SeededRandomNumberGenerator(seed: 2024)
        let a = Match.play(size: 5, blue: engine(200), red: RandomEngine(), rng: &first)
        let b = Match.play(size: 5, blue: engine(200), red: RandomEngine(), rng: &second)
        #expect(a.moves == b.moves)
    }

    @Test("Search beats greedy")
    func beatsGreedy() {
        let rate = Match.winRate(
            size: 5,
            blue: engine(1_200),
            red: GreedyEngine(strategy: .balanced),
            games: 12,
            seed: 4_711
        )
        #expect(rate > 0.8, "search won only \(rate * 100)% against greedy")
    }
}
