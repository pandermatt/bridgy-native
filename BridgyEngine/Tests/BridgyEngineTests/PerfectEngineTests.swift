import Testing
@testable import BridgyEngine

@Suite("Perfect play")
struct PerfectEngineTests {

    @Test("Blue's graph is exactly one edge short of two spanning trees", arguments: 2...20)
    func edgeCountIsOneShort(size: Int) {
        let board = Board(size: size)
        let nodes = size * size - size + 2        // after contracting the two goal rows
        let edges = board.cellCount               // 2n² - 2n + 1
        #expect(nodes == size * size - size + 2)
        #expect(edges == 2 * (nodes - 1) - 1, "the opening move is what closes this gap")
    }

    @Test("The opening leaves two edge-disjoint spanning trees", arguments: 2...12)
    func openingAdmitsAPairing(size: Int) {
        let board = Board(size: size)
        guard let pairing = PairingStrategy(board: board) else {
            Issue.record("no pairing found for size \(size)")
            return
        }
        let nodesAfterOpening = size * size - size + 1
        let trees = pairing.trees

        #expect(trees.count == 2)
        #expect(trees[0].count == nodesAfterOpening - 1)
        #expect(trees[1].count == nodesAfterOpening - 1)
        #expect(trees[0].isDisjoint(with: trees[1]), "an edge cannot be in both trees")

        // Together the trees must account for every cell but the opening, so that
        // whatever red takes, it is always paired with a reply.
        let openingCell = board.index(of: PairingStrategy.opening)
        let covered = trees[0].union(trees[1])
        let expected = Set(0..<board.cellCount).subtracting([openingCell])
        #expect(covered == expected)
    }

    @Test("Perfect beats a random opponent every single time", arguments: [2, 3, 4, 5, 6, 7, 8])
    func beatsRandom(size: Int) {
        var rng = SeededRandomNumberGenerator(seed: UInt64(size) &* 2_654_435_761)
        for game in 0..<25 {
            let final = Match.play(size: size, blue: PerfectEngine(), red: RandomEngine(), rng: &rng)
            #expect(final.winner == .blue, "lost game \(game) at size \(size)")
        }
    }

    @Test("Perfect beats every other engine every single time")
    func beatsEveryone() {
        let opponents: [any Engine] = [
            GreedyEngine(strategy: .aggressive),
            GreedyEngine(strategy: .defensive),
            GreedyEngine(strategy: .balanced),
            ShortestPathEngine(strategy: .balanced, tieBreak: .avoidConnection),
            ShortestPathEngine(strategy: .balanced, tieBreak: .disturbOpponent),
            ShortestPathEngine(strategy: .defensive, tieBreak: .random)
        ]
        var rng = SeededRandomNumberGenerator(seed: 1_964)
        for size in 4...7 {
            for opponent in opponents {
                for game in 0..<5 {
                    let final = Match.play(size: size, blue: PerfectEngine(), red: opponent, rng: &rng)
                    #expect(
                        final.winner == .blue,
                        "lost game \(game) at size \(size) to \(opponent.identifier)"
                    )
                }
            }
        }
    }

    @Test("Perfect never claims perfection from the second seat")
    func declinesAsRed() {
        var state = GameState(size: 5)
        state.apply(Move(kind: .v, row: 2, col: 2))   // blue moves; red is now to play
        #expect(state.current == .red)
        #expect(PerfectEngine.canPlayPerfectly(in: state) == false)
        #expect(PerfectEngine().perfectMove(in: state) == nil)

        // It must still produce a legal move, via the fallback.
        var rng = SeededRandomNumberGenerator(seed: 5)
        let move = PerfectEngine().chooseMove(in: state, rng: &rng)
        #expect(move != nil)
        #expect(state.isLegal(move!))
    }

    @Test("Perfect declines a position that drifted off the pairing")
    func declinesAfterDrift() {
        var state = GameState(size: 5)
        // Blue opens somewhere other than the corner, so no pairing describes this.
        state.apply(Move(kind: .h, row: 1, col: 1))
        state.apply(Move(kind: .v, row: 0, col: 0))
        #expect(state.current == .blue)
        #expect(PerfectEngine().perfectMove(in: state) == nil)
    }
}

@Suite("Pairing cache")
struct PairingCacheTests {

    /// Re-derives the reply from scratch every call, the way the engine used to.
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

    /// Mirrors `PerfectEngine.perfectMove`, which answers the opening itself
    /// before the cache has any prefix to match against.
    private func cachedReply(_ cache: PairingCache, _ state: GameState) -> Move? {
        if state.moves.isEmpty { return PairingStrategy.opening }
        guard state.moves[0] == PairingStrategy.opening else { return nil }
        return cache.reply(board: state.board, history: state.moves)
    }

    @Test("The cache plays exactly what a from-scratch replay would", arguments: [3, 4, 6, 8])
    func matchesReplay(size: Int) {
        let cache = PairingCache()
        var rng = SeededRandomNumberGenerator(seed: UInt64(size) &* 7717)
        var state = GameState(size: size)

        while !state.isOver {
            if state.current == .blue {
                let cached = cachedReply(cache, state)
                let replayed = replayReply(board: state.board, history: state.moves)
                #expect(cached == replayed, "diverged at move \(state.moveCount), size \(size)")
                guard let move = cached else { break }
                state.apply(move)
            } else {
                guard let move = state.legalMoves.randomElement(using: &rng) else { break }
                state.apply(move)
            }
        }
        #expect(state.winner == .blue)
    }

    @Test("A position that is not a continuation rebuilds instead of misreporting")
    func rebuildsAfterDrift() {
        let board = Board(size: 5)
        let cache = PairingCache()

        // Walk a few plies so the cache holds real state.
        var state = GameState(size: 5)
        var rng = SeededRandomNumberGenerator(seed: 4)
        for _ in 0..<4 {
            if state.current == .blue {
                guard let move = cachedReply(cache, state) else { break }
                state.apply(move)
            } else if let move = state.legalMoves.randomElement(using: &rng) {
                state.apply(move)
            }
        }
        #expect(state.moveCount >= 4)

        // A history that shares no prefix must not be answered from the cache.
        let foreign = [Move(kind: .h, row: 1, col: 1), Move(kind: .v, row: 0, col: 1)]
        #expect(cache.reply(board: board, history: foreign) == nil)

        // And the cache still works afterwards for a legitimate continuation.
        #expect(cache.reply(board: board, history: state.moves) != nil)
    }

    /// Guards the cache itself rather than its output. Rebuilding the pairing on
    /// every call costs ~2.4 s for this game; reusing it costs ~30 ms. A threshold
    /// in between catches a silent regression to the old path without being
    /// sensitive to how fast the machine is.
    @Test("A full game's worth of perfect play stays cheap")
    func staysFast() {
        var rng = SeededRandomNumberGenerator(seed: 5)
        let blue = PerfectEngine(fallback: ShortestPathEngine())
        let red = GreedyEngine(strategy: .balanced)
        var final: GameState?
        let elapsed = ContinuousClock().measure {
            final = Match.play(size: 12, blue: blue, red: red, rng: &rng)
        }
        #expect(final?.winner == .blue)
        #expect(elapsed < .seconds(1), "a full 12x12 game took \(elapsed)")
    }

    @Test("Re-asking for the same position is stable")
    func repeatedCallsAgree() {
        let board = Board(size: 6)
        let cache = PairingCache()
        var state = GameState(size: 6)
        var rng = SeededRandomNumberGenerator(seed: 21)
        for _ in 0..<6 {
            if state.current == .blue {
                guard let move = cachedReply(cache, state) else { break }
                state.apply(move)
            } else if let move = state.legalMoves.randomElement(using: &rng) {
                state.apply(move)
            }
        }
        let first = cachedReply(cache, state)
        let second = cachedReply(cache, state)
        let third = cachedReply(cache, state)
        #expect(first != nil)
        #expect(first == second)
        #expect(second == third)
    }
}
