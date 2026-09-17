import Synchronization

/// Blue's winning pairing strategy, maintained move by move.
///
/// Contract blue's top row to one node and its bottom row to another. The
/// resulting graph has `n² - n + 2` nodes and `2n² - 2n + 1` edges — exactly one
/// edge short of `2(V - 1)`, the number needed for two edge-disjoint spanning
/// trees. Blue's opening move contracts one edge and closes that gap, so the
/// rest of the board splits cleanly into two spanning trees `T₁` and `T₂`, with
/// every remaining cell in exactly one of them. That pairing is the strategy.
///
/// When red takes an edge `e` — necessarily from one of the trees — removing it
/// splits that tree in two. Blue replies with an edge from the *other* tree that
/// spans the gap. Because blue's own edges are contracted, both trees are once
/// again spanning and disjoint, and the invariant holds for the rest of the
/// game. Blue can therefore never be cut off.
///
/// This is Oliver Gross's solution to Bridg-It, a special case of Lehman's 1964
/// theorem on the Shannon switching game.
struct PairingStrategy {

    private let board: Board
    /// Contracted endpoints of every cell, before any claiming.
    private let endpoints: [(u: Int, v: Int)]
    /// Contracts the cells blue has claimed.
    private var merged: DisjointSet
    private(set) var trees: [Set<Int>]

    /// Blue's winning opening: the corner vertical.
    static let opening = Move(kind: .v, row: 0, col: 0)

    /// Builds the decomposition for a board where blue has just played `opening`.
    /// Returns `nil` if no pairing exists, which should not happen for a legal
    /// board size but is reported rather than assumed.
    init?(board: Board) {
        self.board = board
        let n = board.size

        // Contract blue's goal lines: row 0 becomes node 0, row n node 1.
        let baseNodeCount = 2 + (n - 1) * n
        func node(ofDot dot: Int) -> Int {
            let row = dot / n
            let col = dot % n
            if row == 0 { return 0 }
            if row == n { return 1 }
            return 2 + (row - 1) * n + col
        }

        var endpoints: [(u: Int, v: Int)] = []
        endpoints.reserveCapacity(board.cellCount)
        for cell in 0..<board.cellCount {
            let (a, b) = board.blueEndpoints(board.move(at: cell))
            endpoints.append((node(ofDot: a), node(ofDot: b)))
        }
        self.endpoints = endpoints

        var merged = DisjointSet(count: baseNodeCount)
        let openingCell = board.index(of: Self.opening)
        merged.union(endpoints[openingCell].u, endpoints[openingCell].v)
        self.merged = merged

        // Renumber the contracted graph and pack what remains.
        var compact = [Int: Int]()
        for base in 0..<baseNodeCount {
            let root = merged.root(base)
            if compact[root] == nil { compact[root] = compact.count }
        }
        var packable: [SpanningTreePacking.Edge] = []
        for cell in 0..<board.cellCount where cell != openingCell {
            let u = compact[merged.root(endpoints[cell].u)]!
            let v = compact[merged.root(endpoints[cell].v)]!
            guard u != v else { continue }
            packable.append(SpanningTreePacking.Edge(id: cell, u: u, v: v))
        }

        guard let packed = SpanningTreePacking.packTwoSpanningTrees(
            nodeCount: compact.count,
            edges: packable
        ) else { return nil }
        self.trees = [packed.first, packed.second]
    }

    /// Blue's reply to red taking `cell`. Returns the cell blue should take.
    mutating func respond(to cell: Int) -> Int? {
        guard let treeIndex = trees.firstIndex(where: { $0.contains(cell) }) else {
            // Every remaining cell belongs to exactly one tree, so this means the
            // position has drifted away from the strategy.
            return nil
        }
        trees[treeIndex].remove(cell)
        let otherIndex = 1 - treeIndex

        // Removing `cell` split its tree. Find which side each node fell on.
        let severed = component(of: merged.root(endpoints[cell].u), in: trees[treeIndex])

        // Any edge of the other tree spanning that cut restores the connection.
        // Take the lowest-numbered one: the choice must not depend on set
        // iteration order, because the whole pairing is replayed from the move
        // history on every turn and has to reproduce itself exactly.
        guard let reply = trees[otherIndex].filter({ candidate in
            let u = severed.contains(merged.root(endpoints[candidate].u))
            let v = severed.contains(merged.root(endpoints[candidate].v))
            return u != v
        }).min() else { return nil }

        trees[otherIndex].remove(reply)
        merged.union(endpoints[reply].u, endpoints[reply].v)
        return reply
    }

    /// Nodes reachable from `start` using only the edges of `tree`.
    private func component(of start: Int, in tree: Set<Int>) -> Set<Int> {
        var adjacency = [Int: [Int]]()
        for cell in tree {
            let u = merged.root(endpoints[cell].u)
            let v = merged.root(endpoints[cell].v)
            adjacency[u, default: []].append(v)
            adjacency[v, default: []].append(u)
        }
        var seen: Set<Int> = [start]
        var stack = [start]
        while let node = stack.popLast() {
            for next in adjacency[node] ?? [] where seen.insert(next).inserted {
                stack.append(next)
            }
        }
        return seen
    }
}

/// Plays Bridg-It perfectly — as blue.
///
/// Blue moving first has a forced win, so this engine simply cannot lose a game
/// it starts. Red has no such strategy: the second player provably loses against
/// best play, so when asked to play red, or handed a position that has drifted
/// off the pairing, it defers to `fallback` rather than pretending.
public struct PerfectEngine: Engine {

    public let fallback: any Engine
    /// Shared by every copy of this value, which is the point — the session holds
    /// one engine for the game and the pairing survives across its turns.
    private let cache = PairingCache()

    public init(fallback: any Engine = ShortestPathEngine(strategy: .balanced, tieBreak: .avoidConnection)) {
        self.fallback = fallback
    }

    public let identifier = "perfect"
    public let displayName = "Perfect"
    public var summary: String {
        "Plays Gross's solution to Bridg-It and cannot be beaten when it moves first. "
        + "Playing second it falls back to search, because the second player has no winning strategy."
    }

    /// Whether this engine can actually play perfectly from here.
    public static func canPlayPerfectly(in state: GameState) -> Bool {
        state.current == .blue && state.moves.count % 2 == 0
    }

    public func chooseMove(in state: GameState, rng: inout SeededRandomNumberGenerator) -> Move? {
        guard !state.isOver else { return nil }
        guard let move = perfectMove(in: state) else {
            return fallback.chooseMove(in: state, rng: &rng)
        }
        return move
    }

    /// The pairing advanced to this position, reusing the cache when the game has
    /// simply continued.
    func perfectMove(in state: GameState) -> Move? {
        guard state.current == .blue, state.moves.count % 2 == 0 else { return nil }
        if state.moves.isEmpty { return PairingStrategy.opening }
        guard state.moves[0] == PairingStrategy.opening else { return nil }
        return cache.reply(board: state.board, history: state.moves)
    }
}

/// Carries the pairing between turns.
///
/// The strategy is genuinely stateful — each reply depends on every reply before
/// it — but `Engine` is a value type, so the original derived it from scratch on
/// every call: a full spanning-tree pack plus a replay of the whole game. That is
/// Θ(n⁴) per move with a Θ(n⁶) tail over a game, which is fine at one move per
/// second and hopeless at fifteen.
///
/// This keeps the strategy alive between calls and feeds it only what is new. The
/// from-scratch path remains as the fallback whenever the position is not a
/// continuation of what the cache has seen — after an undo, a restart, or a blue
/// move that departed from the strategy — so behaviour is unchanged.
final class PairingCache: Sendable {

    private struct Entry {
        var board: Board
        var strategy: PairingStrategy
        /// History already fed to `strategy`, and verified against it.
        var consumed: [Move]
        /// Blue's answer to the last opponent move, not yet seen played.
        var pendingReply: Move?
    }

    private let storage = Mutex<Entry?>(nil)

    /// Blue's move in this position, or `nil` if no pairing describes it.
    func reply(board: Board, history: [Move]) -> Move? {
        storage.withLock { entry in
            var strategy: PairingStrategy
            var consumed: [Move]
            var reply: Move?

            if let existing = entry,
               existing.board == board,
               history.starts(with: existing.consumed) {
                strategy = existing.strategy
                consumed = existing.consumed
                reply = existing.pendingReply
            } else {
                guard let fresh = PairingStrategy(board: board) else { return nil }
                strategy = fresh
                consumed = [PairingStrategy.opening]
                reply = nil
                guard history.starts(with: consumed) else { return nil }
            }

            // Even indices are blue's, odd are the opponent's. Blue's own moves are
            // only checked: if one is not what the pairing said to play, the
            // position has drifted and no pairing describes it.
            var index = consumed.count
            while index < history.count {
                if index.isMultiple(of: 2) {
                    guard let expected = reply, history[index] == expected else { return nil }
                    consumed.append(history[index])
                    reply = nil
                } else {
                    guard let answer = strategy.respond(to: board.index(of: history[index])) else {
                        return nil
                    }
                    consumed.append(history[index])
                    reply = board.move(at: answer)
                }
                index += 1
            }

            entry = Entry(
                board: board,
                strategy: strategy,
                consumed: consumed,
                pendingReply: reply
            )
            return reply
        }
    }
}
