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
