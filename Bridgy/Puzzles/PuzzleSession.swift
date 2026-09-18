import BridgyEngine
import Foundation
import Observation

/// One puzzle being solved: the position, the moves left, and the opponent's
/// best defence after each of yours.
@MainActor
@Observable
final class PuzzleSession {
    enum Size: Int, CaseIterable, Identifiable {
        case small = 4, medium = 5, large = 6
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            }
        }
        var movesToWin: ClosedRange<Int> { self == .large ? 2...4 : 2...3 }
    }

    enum Status: Equatable {
        case loading
        case yourMove
        case defending
        case solved
        /// Your move let the win slip; the position shows what went wrong.
        case missed
        case showingSolution
    }

    var size: Size
    private(set) var puzzle: Puzzle?
    private(set) var state: GameState
    private(set) var status: Status = .loading
    /// Your moves still available to win.
    private(set) var remaining = 0
    /// Counted once per puzzle, for Stats.
    @ObservationIgnored private var counted = false

    private let onFinish: (_ solved: Bool) -> Void

    init(size: Size, onFinish: @escaping (Bool) -> Void) {
        self.size = size
        self.state = GameState(size: size.rawValue)
        self.onFinish = onFinish
    }

    var you: Player? { puzzle?.solver }

    // MARK: - Flow

    func next() async {
        status = .loading
        let size = self.size
        let made = await Task.detached(priority: .userInitiated) { () -> Puzzle? in
            // A few seeds, in case one run of games throws up nothing suitable.
            for _ in 0..<5 {
                let seed = UInt64.random(in: 1...UInt64.max)
                if let puzzle = PuzzleGenerator.make(size: size.rawValue, movesToWin: size.movesToWin, seed: seed) {
                    return puzzle
                }
            }
            return nil
        }.value
        guard let made else { status = .loading; return }
        puzzle = made
        counted = false
        restart()
    }

    func restart() {
        guard let puzzle else { return }
        state = puzzle.state
        remaining = puzzle.movesToWin
        status = .yourMove
    }

    func play(_ move: Move) {
        guard status == .yourMove, let you, state.isLegal(move) else { return }
        state.apply(move)
        remaining -= 1
        if state.winner == you {
            status = .solved
            finish(solved: true)
            return
        }
        let position = state
        let left = remaining
        status = .defending
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (Bool, Move?) in
                var solver = ForcedWinSolver()
                let holds = left > 0 && solver.attackerStillWins(afterMove: position, attacker: you, within: left)
                let reply = solver.bestDefence(position, attacker: you, budget: left)
                return (holds, reply)
            }.value
            guard status == .defending, state == position else { return }
            try? await Task.sleep(for: .milliseconds(350))
            if let reply = outcome.1 { state.apply(reply) }
            if !outcome.0 {
                status = .missed
                finish(solved: false)
            } else {
                status = .yourMove
            }
        }
    }

    /// Plays the winning line from the start, one move at a time.
    func showSolution() async {
        guard let puzzle else { return }
        state = puzzle.state
        remaining = puzzle.movesToWin
        status = .showingSolution
        finish(solved: false)
        let you = puzzle.solver
        var solver = ForcedWinSolver()
        while remaining > 0, status == .showingSolution {
            try? await Task.sleep(for: .milliseconds(700))
            let position = state
            let left = remaining
            let move = await Task.detached { var s = ForcedWinSolver(); return s.winningMove(position, within: left) }.value
            guard let move, status == .showingSolution else { return }
            state.apply(move)
            remaining -= 1
            if state.winner == you { return }
            try? await Task.sleep(for: .milliseconds(500))
            if let reply = solver.bestDefence(state, attacker: you, budget: remaining) { state.apply(reply) }
        }
    }

    private func finish(solved: Bool) {
        guard !counted else { return }
        counted = true
        onFinish(solved)
    }
}
