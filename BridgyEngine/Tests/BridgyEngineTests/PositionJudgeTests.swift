import Testing
@testable import BridgyEngine

@Suite("Position judge")
struct PositionJudgeTests {

    @Test("A decided game is certain")
    func decided() {
        var state = GameState(size: 2)
        var rng = SeededRandomNumberGenerator(seed: 3)
        while !state.isOver { state.apply(state.legalMoves.randomElement(using: &rng)!) }
        #expect(PositionJudge.downChance(state) == (state.winner == .blue ? 1 : 0))
    }

    @Test("A forced win for the side to move reads as certain")
    func forced() throws {
        let puzzle = try #require(PuzzleGenerator.make(size: 4, movesToWin: 2...2, seed: 11))
        let chance = PositionJudge.downChance(puzzle.state)
        #expect(chance == (puzzle.state.current == .blue ? 1 : 0))
    }

    @Test("The chart isn't flat: a game with a blunder shows a swing")
    func swings() {
        // Medium against Random: the random side keeps throwing the game away.
        var state = GameState(size: 5)
        var rng = SeededRandomNumberGenerator(seed: 7)
        let medium = ShortestPathEngine(strategy: .balanced, tieBreak: .disturbOpponent)
        let random = RandomEngine()
        while !state.isOver {
            let engine: any Engine = state.current == .blue ? random : medium
            state.apply(engine.chooseMove(in: state, rng: &rng)!)
        }
        let chances = PositionJudge.history(moves: state.moves, board: state.board, counts: Array(0...state.moveCount))
        let values = chances.values
        #expect(values.max()! - values.min()! > 0.5)
        #expect(!PositionJudge.turningPoints(in: chances, threshold: 0.2).isEmpty)
    }

    @Test("The same position always reads the same")
    func stable() {
        var state = GameState(size: 6)
        state.apply(Move(kind: .v, row: 2, col: 2))
        #expect(PositionJudge.downChance(state) == PositionJudge.downChance(state))
    }

    @Test("Smoothing cancels a move-by-move sawtooth and keeps certainties")
    func smoothing() {
        let saw: [Int: Double] = [0: 0.6, 1: 0.4, 2: 0.6, 3: 0.4, 4: 0.6, 5: 1]
        let smooth = PositionJudge.smoothed(saw)
        for count in 1...3 { #expect(abs(smooth[count]! - 0.5) < 1e-9) }
        #expect(smooth[5] == 1)
    }
}
