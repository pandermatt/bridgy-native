import Testing
@testable import BridgyEngine

/// Bridg-It looks the same to Across as to Down once the board is turned on
/// its diagonal: transposing swaps the dot lattices, maps every cell onto one
/// of the same family, and turns left-to-right into top-to-bottom. Everything
/// an engine computes about one colour in a position must therefore equal what
/// it computes about the other colour in the transposed position, or that
/// engine is playing one colour differently from the other.
@Suite("Colour symmetry")
struct ColourSymmetryTests {

    static func transpose(_ move: Move) -> Move {
        Move(kind: move.kind, row: move.col, col: move.row)
    }

    /// The same position, turned on its diagonal with the colours swapped.
    static func mirror(_ state: GameState) -> GameState {
        let board = state.board
        var owners = [Player?](repeating: nil, count: board.cellCount)
        for cell in 0..<board.cellCount {
            let image = board.index(of: transpose(board.move(at: cell)))
            owners[image] = state.cells[cell]?.opponent
        }
        return GameState(board: board, owners: owners, toMove: state.current.opponent)
    }

    static func positions() -> [GameState] {
        var result: [GameState] = []
        for size in [3, 4, 6, 9, 12] {
            for seed in 0..<12 as Range<UInt64> {
                var rng = SeededRandomNumberGenerator(seed: seed &* 31 &+ UInt64(size))
                var state = GameState(size: size)
                let length = Int(seed) * state.board.cellCount / 30
                for _ in 0..<length {
                    let safe = state.legalMoves.filter { !state.wouldWin($0, for: state.current) }
                    guard let move = safe.randomElement(using: &rng) else { break }
                    state.apply(move)
                }
                result.append(state)
            }
        }
        return result
    }

    @Test("Mirroring twice gives the position back")
    func involution() {
        for state in Self.positions() {
            let back = Self.mirror(Self.mirror(state))
            #expect(back.cells == state.cells)
            #expect(back.current == state.current)
        }
    }

    @Test("Shortest routes are the same length for either colour, mirrored")
    func distances() {
        for state in Self.positions() {
            let image = Self.mirror(state)
            for player in Player.allCases {
                let here = ShortestPath.search(in: state, for: player, graph: PlayerGraph(board: state.board, player: player))
                let there = ShortestPath.search(
                    in: image, for: player.opponent, graph: PlayerGraph(board: state.board, player: player.opponent)
                )
                #expect(here.distance == there.distance)
                let mapped = Set(here.candidateCells.map { state.board.index(of: Self.transpose(state.board.move(at: $0))) })
                #expect(mapped == Set(there.candidateCells), "Candidate cells differ")
            }
        }
    }

    @Test("Connection ratings are the same for either colour, mirrored")
    func ratings() {
        for state in Self.positions() {
            let image = Self.mirror(state)
            for player in Player.allCases {
                var here = ConnectionSummary(state: state, player: player, graph: PlayerGraph(board: state.board, player: player))
                var there = ConnectionSummary(
                    state: image, player: player.opponent, graph: PlayerGraph(board: state.board, player: player.opponent)
                )
                for move in state.legalMoves {
                    #expect(here.rate(move) == there.rate(Self.transpose(move)), "\(player) \(move)")
                }
            }
        }
    }
}
