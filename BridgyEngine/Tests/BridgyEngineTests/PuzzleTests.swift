import Testing
@testable import BridgyEngine

/// Exhaustive: every move for both sides.
private func bruteForce(_ state: GameState, attacker: Player, budget: Int) -> Bool {
    if state.isOver || budget < 1 { return false }
    for cell in state.legalMoveIndices {
        var next = state
        next.apply(state.board.move(at: cell))
        if next.winner == attacker { return true }
        if budget == 1 || next.isOver { continue }
        var holds = true
        for reply in next.legalMoveIndices {
            var after = next
            after.apply(next.board.move(at: reply))
            if after.winner != nil || !bruteForce(after, attacker: attacker, budget: budget - 1) {
                holds = false
                break
            }
        }
        if holds { return true }
    }
    return false
}

private func positions(size: Int, count: Int, seed: UInt64) -> [GameState] {
    var rng = SeededRandomNumberGenerator(seed: seed)
    var result: [GameState] = []
    while result.count < count {
        var state = GameState(size: size)
        let length = Int.random(in: 0..<(state.board.cellCount * 2 / 3), using: &rng)
        for _ in 0..<length {
            guard let move = state.legalMoves.randomElement(using: &rng) else { break }
            state.apply(move)
            if state.isOver { break }
        }
        if !state.isOver { result.append(state) }
    }
    return result
}

@Suite("Puzzles")
struct PuzzleTests {

    @Test("The pruned solver agrees with exhaustive search", arguments: [(3, 3), (4, 2)])
    func agreesWithBruteForce(size: Int, budget: Int) {
        for state in positions(size: size, count: 120, seed: UInt64(size * 7 + budget)) {
            for k in 1...budget {
                var solver = ForcedWinSolver()
                let fast = solver.canForceWin(state, within: k)
                let slow = bruteForce(state, attacker: state.current, budget: k)
                #expect(fast == slow, "size \(size), k \(k), moves \(state.moves)")
            }
        }
    }

    @Test("Generated puzzles are wins in exactly the stated number of moves", arguments: [4, 5, 6])
    func generated(size: Int) {
        for seed in 1...3 as ClosedRange<UInt64> {
            guard let puzzle = PuzzleGenerator.make(size: size, seed: seed) else {
                Issue.record("no puzzle for size \(size) seed \(seed)")
                continue
            }
            var solver = ForcedWinSolver()
            let wins = solver.canForceWin(puzzle.state, within: puzzle.movesToWin)
            let winsSooner = puzzle.movesToWin > 1 && solver.canForceWin(puzzle.state, within: puzzle.movesToWin - 1)
            #expect(wins)
            #expect(!winsSooner)
        }
    }

    @Test("Following the solver's moves against its best defence wins in time")
    func solutionPlaysOut() {
        guard let puzzle = PuzzleGenerator.make(size: 5, seed: 42) else { Issue.record("no puzzle"); return }
        var solver = ForcedWinSolver()
        var state = puzzle.state
        let me = puzzle.solver
        for remaining in stride(from: puzzle.movesToWin, through: 1, by: -1) {
            guard let move = solver.winningMove(state, within: remaining) else {
                Issue.record("no winning move with \(remaining) to go"); return
            }
            state.apply(move)
            if state.winner == me { return }
            guard let reply = solver.bestDefence(state, attacker: me, budget: remaining - 1) else { break }
            state.apply(reply)
        }
        #expect(state.winner == me)
    }
}
