import Testing
@testable import BridgyEngine

@Suite("Ported engines")
struct EngineTests {

    private var allEngines: [any Engine] {
        [
            RandomEngine(),
            GreedyEngine(strategy: .aggressive),
            GreedyEngine(strategy: .defensive),
            GreedyEngine(strategy: .balanced),
            ShortestPathEngine(strategy: .aggressive, tieBreak: .longestConnection),
            ShortestPathEngine(strategy: .defensive, tieBreak: .random),
            ShortestPathEngine(strategy: .balanced, tieBreak: .avoidConnection),
            ShortestPathEngine(strategy: .balanced, tieBreak: .disturbOpponent)
        ]
    }

    @Test("On an empty board both players are exactly n moves from winning", arguments: 2...12)
    func openingDistance(size: Int) {
        let state = GameState(size: size)
        #expect(ShortestPath.movesToWin(in: state, for: .blue) == size)
        #expect(ShortestPath.movesToWin(in: state, for: .red) == size)
    }

    @Test("A required-cells route really is a winning plan", arguments: 2...8)
    func routeIsAPlan(size: Int) {
        var state = GameState(size: size)
        var rng = SeededRandomNumberGenerator(seed: UInt64(size) &* 977)
        // Scatter a few moves so the route is not just a straight column.
        for _ in 0..<(size * 2) where !state.isOver {
            if let move = state.legalMoves.randomElement(using: &rng) { state.apply(move) }
        }
        guard !state.isOver else { return }

        let player = state.current
        let graph = PlayerGraph(board: state.board, player: player)
        let path = ShortestPath.search(in: state, for: player, graph: graph)
        guard let distance = path.distance else { return }
        #expect(path.requiredCells.count == distance)

        // Owning what it already has, plus every cell on the route, must connect
        // the two goal lines. Built independently of GameState's own bookkeeping.
        var sets = DisjointSet(count: graph.nodeCount)
        for cell in 0..<state.board.cellCount where state.cells[cell] == player {
            let (a, b) = state.board.endpoints(state.board.move(at: cell), for: player)
            sets.union(a, b)
        }
        for cell in path.requiredCells {
            #expect(state.cells[cell] == nil, "route included a cell that is already taken")
            let (a, b) = state.board.endpoints(state.board.move(at: cell), for: player)
            sets.union(a, b)
        }
        for edge in graph.neighbors[graph.source] { sets.union(graph.source, edge.node) }
        for edge in graph.neighbors[graph.sink] { sets.union(graph.sink, edge.node) }
        let crossed = sets.areConnected(graph.source, graph.sink)
        #expect(crossed, "a shortest route of \(distance) moves did not actually cross the board")
    }

    @Test("Engines only ever return legal moves")
    func movesAreLegal() {
        var rng = SeededRandomNumberGenerator(seed: 4242)
        for engine in allEngines {
            for size in [2, 3, 5, 8] {
                var state = GameState(size: size)
                while !state.isOver {
                    guard let move = engine.chooseMove(in: state, rng: &rng) else {
                        Issue.record("\(engine.identifier) returned nil with \(state.legalMoves.count) moves available")
                        break
                    }
                    #expect(state.isLegal(move), "\(engine.identifier) returned an illegal move \(move)")
                    state.apply(move)
                }
                #expect(state.winner != nil)
            }
        }
    }

    /// A position where blue completes a column by playing v(2,0).
    private func blueOneMoveFromWinning() -> GameState {
        var state = GameState(size: 3)
        for move in [
            Move(kind: .v, row: 0, col: 0),  // blue
            Move(kind: .v, row: 0, col: 2),  // red, harmlessly far away
            Move(kind: .v, row: 1, col: 0),  // blue
            Move(kind: .v, row: 1, col: 2)   // red
        ] {
            state.apply(move)
        }
        return state
    }

    @Test("Every engine that looks at its own connection takes an available win")
    func takesTheWin() {
        let state = blueOneMoveFromWinning()
        #expect(state.current == .blue)
        #expect(state.wouldWin(Move(kind: .v, row: 2, col: 0), for: .blue))

        let attackers: [any Engine] = [
            GreedyEngine(strategy: .aggressive),
            GreedyEngine(strategy: .balanced),
            ShortestPathEngine(strategy: .aggressive, tieBreak: .longestConnection),
            ShortestPathEngine(strategy: .balanced, tieBreak: .avoidConnection)
        ]
        for engine in attackers {
            var rng = SeededRandomNumberGenerator(seed: 11)
            let move = engine.chooseMove(in: state, rng: &rng)
            #expect(move == Move(kind: .v, row: 2, col: 0), "\(engine.identifier) walked past a win")
        }
    }

    @Test("Every engine that watches its opponent blocks an imminent loss")
    func blocksTheLoss() {
        var state = blueOneMoveFromWinning()
        // Hand the move to red, which must now block v(2,0).
        state.apply(Move(kind: .h, row: 1, col: 1))
        #expect(state.current == .red)

        let defenders: [any Engine] = [
            GreedyEngine(strategy: .defensive),
            GreedyEngine(strategy: .balanced),
            ShortestPathEngine(strategy: .defensive, tieBreak: .random),
            ShortestPathEngine(strategy: .balanced, tieBreak: .avoidConnection)
        ]
        for engine in defenders {
            var rng = SeededRandomNumberGenerator(seed: 12)
            let move = engine.chooseMove(in: state, rng: &rng)
            #expect(move == Move(kind: .v, row: 2, col: 0), "\(engine.identifier) let blue walk in")
        }
    }

    @Test("Greedy beats random convincingly")
    func greedyBeatsRandom() {
        let rate = Match.winRate(
            size: 6,
            blue: GreedyEngine(strategy: .balanced),
            red: RandomEngine(),
            games: 60,
            seed: 20_250_917
        )
        #expect(rate > 0.9, "greedy won only \(rate * 100)% against random")
    }

    @Test("Pathfinder beats greedy convincingly")
    func pathfinderBeatsGreedy() {
        let rate = Match.winRate(
            size: 6,
            blue: ShortestPathEngine(strategy: .balanced, tieBreak: .avoidConnection),
            red: GreedyEngine(strategy: .balanced),
            games: 40,
            seed: 777
        )
        #expect(rate > 0.85, "pathfinder won only \(rate * 100)% against greedy")
    }

    /// Red is the losing seat: Bridg-It is a first-player win, so even perfect
    /// play cannot take every game from blue. The bar is that a strong red turns
    /// a weak blue's structural advantage into a losing record most of the time.
    @Test("Pathfinder holds up even from the losing seat")
    func pathfinderAsRed() {
        let blueWins = Match.winRate(
            size: 6,
            blue: GreedyEngine(strategy: .balanced),
            red: ShortestPathEngine(strategy: .balanced, tieBreak: .avoidConnection),
            games: 40,
            seed: 31_337
        )
        #expect(blueWins < 0.45, "greedy-as-blue won \(blueWins * 100)% against pathfinder-as-red")
    }
}
