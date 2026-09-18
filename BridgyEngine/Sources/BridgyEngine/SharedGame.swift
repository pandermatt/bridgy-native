import Foundation

/// What two devices playing one game over SharePlay say to each other.
public enum SharedGameMessage: Codable, Sendable, Equatable {
    /// "I'm starting a game of this size, and I play Down."
    case start(size: Int, starter: UUID)
    /// The move with this number (counting from zero) went on this cell.
    case move(index: Int, cell: Int)
    /// The whole game so far, for someone joining late or who missed a move.
    case history(size: Int, starter: UUID, cells: [Int])
    /// "I'm out of step; send me the game."
    case requestHistory
}

/// One side's record of a shared game, and the rules for keeping two of them
/// in agreement.
///
/// Messages can arrive twice, late, or not at all. Every move carries its
/// number, so a repeat is recognised and dropped, and a gap is noticed and
/// mended by asking for the whole history — which is just the list of cells,
/// replayed. Two people pressing "start" at once is settled the same way on
/// both sides: the lower participant id plays Down.
public struct SharedGameLedger: Sendable {
    public enum Reaction: Equatable, Sendable {
        case none
        /// A new game began; build a board of this state.
        case began
        /// The other side's move, to show.
        case applied(Move)
        /// Our copy was replaced wholesale; redraw from `state`.
        case replaced
        /// We can't follow; send this reply.
        case reply(SharedGameMessage)
    }

    public let me: UUID
    public private(set) var state: GameState?
    /// Whoever plays Down: the one who started.
    public private(set) var down: UUID?

    public init(me: UUID) {
        self.me = me
    }

    public var myColour: Player? {
        guard let down else { return nil }
        return down == me ? .blue : .red
    }

    public var isMyTurn: Bool {
        guard let state, let myColour else { return false }
        return !state.isOver && state.current == myColour
    }

    /// Starts a game here; send the returned message.
    public mutating func start(size: Int) -> SharedGameMessage {
        state = GameState(size: size)
        down = me
        return .start(size: size, starter: me)
    }

    /// A move made here. Nil if it isn't this side's turn or isn't legal.
    public mutating func play(_ move: Move) -> SharedGameMessage? {
        guard isMyTurn, var state, state.isLegal(move) else { return nil }
        let index = state.moveCount
        state.apply(move)
        self.state = state
        return .move(index: index, cell: state.board.index(of: move))
    }

    public func historyMessage() -> SharedGameMessage? {
        guard let state, let down else { return nil }
        return .history(size: state.board.size, starter: down, cells: state.moves.map(state.board.index(of:)))
    }

    public mutating func receive(_ message: SharedGameMessage, from sender: UUID) -> Reaction {
        switch message {
        case .start(let size, let starter):
            // Both started at once: the lower id plays Down, on both sides.
            if let down, down == me, state?.moveCount == 0, starter != me {
                guard starter.uuidString < me.uuidString else { return .none }
            }
            state = GameState(size: size)
            down = starter
            return .began

        case .move(let index, let cell):
            guard var state else { return .reply(.requestHistory) }
            if index < state.moveCount {
                // Seen already. Only worrying if it disagrees with what we have.
                let seen = state.board.index(of: state.moves[index])
                return seen == cell ? .none : .reply(.requestHistory)
            }
            guard index == state.moveCount, cell < state.board.cellCount else {
                return .reply(.requestHistory)
            }
            let move = state.board.move(at: cell)
            guard state.isLegal(move), state.current != myColour else { return .reply(.requestHistory) }
            state.apply(move)
            self.state = state
            return .applied(move)

        case .history(let size, let starter, let cells):
            // Take the longer game: the other side may simply be behind.
            if let state, state.board.size == size, down == starter, state.moveCount >= cells.count {
                return .none
            }
            var replay = GameState(size: size)
            for cell in cells {
                guard cell < replay.board.cellCount, replay.apply(replay.board.move(at: cell)) else { break }
            }
            state = replay
            down = starter
            return .replaced

        case .requestHistory:
            return historyMessage().map { .reply($0) } ?? .none
        }
    }
}
