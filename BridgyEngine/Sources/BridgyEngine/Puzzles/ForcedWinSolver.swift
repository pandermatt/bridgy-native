/// Answers "can the side to move force a win within k of its own moves?"
///
/// An AND/OR search: the attacker needs one move that wins against every
/// defence. Two facts about Bridg-It keep it small.
///
/// - A route only ever gets longer as the defender takes cells, so a cell that
///   lies on no route of cost ≤ k now can never be part of a chain finished in
///   k moves. The attacker only ever considers cells on such routes — plus the
///   one cell that stops the defender winning on the spot.
/// - Likewise a defender move matters only if it touches one of those routes,
///   or brings the defender within a move of winning itself (a threat the
///   attacker then has to spend a move on). Every other reply leaves the
///   attacker's position exactly as good, so it need not be searched.
///
/// The tests check this pruning against an exhaustive search on small boards.
public struct ForcedWinSolver {
    private var table: [Key: Bool] = [:]

    private struct Key: Hashable {
        let cells: [Player?]
        let current: Player
        let budget: Int
    }

    public init() {}

    /// Whether the side to move in `state` can force a win within `budget`
    /// of its own moves.
    public mutating func canForceWin(_ state: GameState, within budget: Int) -> Bool {
        attackerWins(state, budget: budget)
    }

    /// The fewest of its own moves in which the side to move can force a win,
    /// searching up to `limit`; nil if none.
    public mutating func shortestForcedWin(_ state: GameState, limit: Int) -> Int? {
        for budget in 1...max(1, limit) where attackerWins(state, budget: budget) { return budget }
        return nil
    }

    /// A move that keeps a win within `budget` forced, if there is one.
    public mutating func winningMove(_ state: GameState, within budget: Int) -> Move? {
        guard !state.isOver else { return nil }
        let attacker = state.current
        for cell in attackerCandidates(state, budget: budget) {
            var next = state
            next.apply(state.board.move(at: cell))
            if next.winner == attacker { return state.board.move(at: cell) }
            if budget > 1, defenderLoses(next, attacker: attacker, budget: budget - 1) {
                return state.board.move(at: cell)
            }
        }
        return nil
    }

    /// Whether, with the defender to move, the attacker still forces a win
    /// within `budget` of its moves whatever the defender does.
    public mutating func attackerStillWins(afterMove state: GameState, attacker: Player, within budget: Int) -> Bool {
        if state.winner == attacker { return true }
        if state.isOver || budget < 1 { return false }
        return defenderLoses(state, attacker: attacker, budget: budget)
    }

    /// The defence that holds out longest: a reply after which the attacker
    /// can no longer force the win if there is one, otherwise the one that
    /// makes the attacker take the most moves.
    public mutating func bestDefence(_ state: GameState, attacker: Player, budget: Int) -> Move? {
        guard !state.isOver else { return nil }
        var best: (move: Move, needed: Int)?
        for cell in 0..<state.board.cellCount where state.cells[cell] == nil {
            let move = state.board.move(at: cell)
            var next = state
            next.apply(move)
            if next.winner != nil { return move }  // the defender wins outright
            let needed = shortestForcedWin(next, limit: budget) ?? (budget + 1)
            if best == nil || needed > best!.needed { best = (move, needed) }
            if needed > budget { break }
        }
        return best?.move
    }

    // MARK: - Search

    private mutating func attackerWins(_ state: GameState, budget: Int) -> Bool {
        if state.isOver || budget < 1 { return false }
        let attacker = state.current
        guard let distance = ShortestPath.movesToWin(in: state, for: attacker), distance <= budget else {
            return false
        }
        let key = Key(cells: state.cells, current: attacker, budget: budget)
        if let known = table[key] { return known }

        var result = false
        for cell in attackerCandidates(state, budget: budget) {
            var next = state
            next.apply(state.board.move(at: cell))
            if next.winner == attacker { result = true; break }
            if budget > 1, defenderLoses(next, attacker: attacker, budget: budget - 1) { result = true; break }
        }
        table[key] = result
        return result
    }

    /// Defender to move: true if every reply still leaves the attacker a
    /// forced win within `budget`.
    private mutating func defenderLoses(_ state: GameState, attacker: Player, budget: Int) -> Bool {
        guard let distance = ShortestPath.movesToWin(in: state, for: attacker), distance <= budget else {
            return false
        }
        let key = Key(cells: state.cells, current: state.current, budget: budget)
        if let known = table[key] { return known }

        var result = true
        for cell in defenderCandidates(state, attacker: attacker, budget: budget) {
            var next = state
            next.apply(state.board.move(at: cell))
            if next.winner == attacker.opponent || !attackerWins(next, budget: budget) {
                result = false
                break
            }
        }
        table[key] = result
        return result
    }

    // MARK: - Candidates

    /// Attacker moves worth trying: cells on a route of cost ≤ budget, and any
    /// cell the defender would win with next.
    private func attackerCandidates(_ state: GameState, budget: Int) -> [Int] {
        let attacker = state.current
        var cells = ShortestPath.cellsOnRoutes(in: state, for: attacker, within: budget)
        for cell in 0..<state.board.cellCount where state.cells[cell] == nil
            && state.wouldWin(state.board.move(at: cell), for: attacker.opponent)
            && !cells.contains(cell) {
            cells.append(cell)
        }
        return cells
    }

    /// Defender replies worth trying: cells on the attacker's routes of cost ≤
    /// budget, plus cells that bring the defender to within one move.
    private func defenderCandidates(_ state: GameState, attacker: Player, budget: Int) -> [Int] {
        var cells = ShortestPath.cellsOnRoutes(in: state, for: attacker, within: budget)
        let defender = attacker.opponent
        if let own = ShortestPath.movesToWin(in: state, for: defender), own <= 2 {
            for cell in ShortestPath.cellsOnRoutes(in: state, for: defender, within: own) where !cells.contains(cell) {
                cells.append(cell)
            }
        }
        return cells
    }
}

extension ShortestPath {
    /// Every empty cell on some route of cost ≤ `budget` for `player`.
    public static func cellsOnRoutes(in state: GameState, for player: Player, within budget: Int) -> [Int] {
        let graph = PlayerGraph(board: state.board, player: player)
        var parentNode: [Int] = []
        var parentCell: [Int] = []
        let forward = distances(in: state, for: player, graph: graph, from: graph.source,
                                parentNode: &parentNode, parentCell: &parentCell)
        let backward = distances(in: state, for: player, graph: graph, from: graph.sink,
                                 parentNode: &parentNode, parentCell: &parentCell)
        var cells: [Int] = []
        for cell in 0..<state.board.cellCount where state.cells[cell] == nil {
            let (a, b) = state.board.endpoints(state.board.move(at: cell), for: player)
            func through(_ x: Int, _ y: Int) -> Int {
                forward[x] == unreachable || backward[y] == unreachable ? unreachable : forward[x] + 1 + backward[y]
            }
            if min(through(a, b), through(b, a)) <= budget { cells.append(cell) }
        }
        return cells
    }
}
