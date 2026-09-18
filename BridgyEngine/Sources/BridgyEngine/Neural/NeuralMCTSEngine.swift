import Foundation

/// Tree search guided by a trained network, AlphaZero style.
///
/// Where `MCTSEngine` plays each line out at random to learn how it ends, this
/// asks the network — once for which moves look worth trying (the priors) and
/// once for who is winning (the value) — and searches with PUCT: a child is
/// visited in proportion to how good it has proved and how promising the
/// network thought it was, discounted by how often it has been tried already.
public struct NeuralMCTSEngine: Engine {
    public let network: NeuralNetwork
    /// Network evaluations per move. At one, it plays the network's first
    /// instinct with no search at all.
    public let simulations: Int
    /// PUCT exploration weight.
    public let exploration: Float
    /// For this many opening moves it picks in proportion to visits rather than
    /// taking the most visited, so repeated games between the same two engines
    /// are not all the same game.
    public let exploratoryMoves: Int
    public let displayName: String

    public init(
        network: NeuralNetwork,
        simulations: Int = 200,
        exploration: Float = 1.5,
        exploratoryMoves: Int = 0,
        name: String = "Agent"
    ) {
        self.network = network
        self.simulations = max(1, simulations)
        self.exploration = exploration
        self.exploratoryMoves = exploratoryMoves
        self.displayName = name
    }

    public var identifier: String { "neural" }
    public var summary: String {
        "A network trained by playing itself, choosing where to look and judging positions for a tree search."
    }

    /// How the search spread its visits over the moves from the root.
    public struct SearchResult: Sendable {
        public var visits: [(cell: Int, count: Int)]
        /// The root's value to the player to move, as the search sees it.
        public var value: Float
    }

    public func chooseMove(in state: GameState, rng: inout SeededRandomNumberGenerator) -> Move? {
        guard !state.isOver else { return nil }
        if let decisive = Self.decisiveMove(in: state) { return decisive }

        if simulations == 1 {
            let judgement = network.judge(state)
            let best = judgement.priors.max { $0.prior < $1.prior }
            return best.map { state.board.move(at: $0.cell) }
        }

        let result = search(state, rng: &rng)
        let temperature: Float = state.moveCount < exploratoryMoves ? 1 : 0
        guard let cell = Self.pick(result.visits, temperature: temperature, rng: &rng) else {
            return state.legalMoves.randomElement(using: &rng)
        }
        return state.board.move(at: cell)
    }

    /// A move that wins at once, or else one that stops the opponent winning at once.
    static func decisiveMove(in state: GameState) -> Move? {
        let me = state.current
        var block: Move?
        for cell in 0..<state.board.cellCount where state.cells[cell] == nil {
            let move = state.board.move(at: cell)
            if state.wouldWin(move, for: me) { return move }
            if block == nil, state.wouldWin(move, for: me.opponent) { block = move }
        }
        return block
    }

    /// Picks a cell from visit counts: the most visited at temperature zero,
    /// otherwise in proportion to `count^(1/temperature)`.
    public static func pick(
        _ visits: [(cell: Int, count: Int)],
        temperature: Float,
        rng: inout SeededRandomNumberGenerator
    ) -> Int? {
        guard !visits.isEmpty else { return nil }
        guard temperature > 0 else { return visits.max { $0.count < $1.count }?.cell }
        let weights = visits.map { powf(Float($0.count), 1 / temperature) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return visits.randomElement(using: &rng)?.cell }
        var target = Float.random(in: 0..<total, using: &rng)
        for (entry, weight) in zip(visits, weights) {
            if target < weight { return entry.cell }
            target -= weight
        }
        return visits.last?.cell
    }

    // MARK: - Search

    private struct Node {
        var cell: Int32
        var prior: Float
        var visits: Int32 = 0
        /// Summed from the side of the player who moved *into* this node.
        var valueSum: Float = 0
        var firstChild: Int32 = -1
        var childCount: Int32 = 0
    }

    /// Runs the search and reports the root's visit counts.
    ///
    /// `rootNoise` mixes Dirichlet noise into the root's priors, as self-play
    /// does so that it keeps trying moves the network has written off.
    public func search(
        _ state: GameState,
        rng: inout SeededRandomNumberGenerator,
        rootNoise: (alpha: Double, fraction: Float)? = nil
    ) -> SearchResult {
        var nodes: [Node] = [Node(cell: -1, prior: 1)]
        nodes.reserveCapacity(simulations * 8)
        var path: [Int] = []
        var movers: [Player] = []

        for simulation in 0..<simulations {
            if simulation > 0, Task.isCancelled { break }
            var position = state
            var index = 0
            path.removeAll(keepingCapacity: true)
            movers.removeAll(keepingCapacity: true)
            path.append(0)

            // Selection.
            while nodes[index].childCount > 0, !position.isOver {
                index = selectChild(of: index, in: nodes)
                movers.append(position.current)
                position.apply(position.board.move(at: Int(nodes[index].cell)))
                path.append(index)
            }

            // Expansion and evaluation, as a value from Down's side.
            let valueForBlue: Float
            if let winner = position.winner {
                valueForBlue = winner == .blue ? 1 : -1
            } else {
                let symmetry = Symmetry.allCases.randomElement(using: &rng) ?? .identity
                let judgement = network.judge(position, symmetry: symmetry)
                var priors = judgement.priors.map(\.prior)
                if index == 0, let rootNoise {
                    let noise = Gaussian.dirichlet(count: priors.count, alpha: rootNoise.alpha, using: &rng)
                    for i in priors.indices {
                        priors[i] = (1 - rootNoise.fraction) * priors[i] + rootNoise.fraction * Float(noise[i])
                    }
                }
                nodes[index].firstChild = Int32(nodes.count)
                nodes[index].childCount = Int32(priors.count)
                for (entry, prior) in zip(judgement.priors, priors) {
                    nodes.append(Node(cell: Int32(entry.cell), prior: prior))
                }
                valueForBlue = position.current == .blue ? judgement.value : -judgement.value
            }

            // Backup. The root has no mover; it only counts visits.
            nodes[0].visits += 1
            for (step, node) in path.dropFirst().enumerated() {
                nodes[node].visits += 1
                nodes[node].valueSum += movers[step] == .blue ? valueForBlue : -valueForBlue
            }
        }

        let root = nodes[0]
        guard root.childCount > 0 else { return SearchResult(visits: [], value: 0) }
        let children = Int(root.firstChild)..<Int(root.firstChild + root.childCount)
        let visits = children.map { (cell: Int(nodes[$0].cell), count: Int(nodes[$0].visits)) }
        let visited = children.filter { nodes[$0].visits > 0 }
        let total = visited.reduce(Float(0)) { $0 + nodes[$1].valueSum }
        let count = visited.reduce(Float(0)) { $0 + Float(nodes[$1].visits) }
        return SearchResult(visits: visits, value: count > 0 ? total / count : 0)
    }

    private func selectChild(of parent: Int, in nodes: [Node]) -> Int {
        let node = nodes[parent]
        let scale = exploration * Float(node.visits).squareRoot()
        var best = Int(node.firstChild)
        var bestScore = -Float.infinity
        for child in Int(node.firstChild)..<Int(node.firstChild + node.childCount) {
            let c = nodes[child]
            let q = c.visits > 0 ? c.valueSum / Float(c.visits) : 0
            let score = q + scale * c.prior / Float(1 + c.visits)
            if score > bestScore {
                bestScore = score
                best = child
            }
        }
        return best
    }
}
