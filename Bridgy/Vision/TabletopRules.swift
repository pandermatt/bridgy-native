#if os(visionOS)
import BridgyEngine
import Foundation
import Synchronization
import TabletopKit

/// What the interaction delegate is allowed to know, without an actor.
///
/// TabletopKit calls the delegate outside any isolation and hands it a
/// non-Sendable interaction object, so the rules cannot simply be read across
/// the boundary. This is the small, plain, Sendable answer to "where may this
/// bridge go right now", republished after every confirmed move — the same
/// `Mutex` approach the engine's pairing cache already uses.
final class PlayableGaps: Sendable {
    private struct Contents {
        var owners: [EquipmentIdentifier: BoardSide] = [:]
        var destinations: [BoardSide: [EquipmentIdentifier]] = [:]
    }
    private let storage = Mutex(Contents())

    func republish(owners: [EquipmentIdentifier: BoardSide], destinations: [BoardSide: [EquipmentIdentifier]]) {
        storage.withLock { $0 = Contents(owners: owners, destinations: destinations) }
    }

    /// The gaps this piece may legally be set down on, or empty when it is not
    /// this side's turn.
    func destinations(forPiece piece: EquipmentIdentifier) -> [EquipmentIdentifier] {
        storage.withLock { contents in
            guard let side = contents.owners[piece] else { return [] }
            return contents.destinations[side] ?? []
        }
    }
}

/// The rules of Bridg-It, enforced against TabletopKit's proposed moves.
///
/// Two stores, one direction. `GameState` decides what is legal — it is the
/// thing with the tests behind it — and TabletopKit's table is the visual and
/// interaction layer. A drag is proposed, `validateAction` asks the engine, and
/// TabletopKit rolls the bridge back into the tray on a no.
@MainActor
final class BridgyRules {

    private(set) var state: GameState
    /// Who is holding each seat, so a computer can answer a human's bridge.
    private let seats: [BoardSide: Seat]
    private let slotIDByCell: [Int: EquipmentIdentifier]
    private let cellBySlotID: [EquipmentIdentifier: Int]
    private let ownerByPieceID: [EquipmentIdentifier: BoardSide]

    /// Pieces still in the tray, per side, in the order they will be used.
    private var spare: [BoardSide: [EquipmentIdentifier]]

    private weak var game: TabletopGame?
    private var engines: [BoardSide: any Engine] = [:]
    private var rng = SeededRandomNumberGenerator(seed: 0x8123)

    /// Called after every confirmed move so the scene can redraw.
    var onChange: ((GameState) -> Void)?

    /// Read by the interaction delegate, which has no actor to read from.
    let gaps = PlayableGaps()

    init(board: Board, seats: [BoardSide: Seat], slots: [BridgeSlot], pieces: [BridgePiece]) {
        self.state = GameState(board: board)
        self.seats = seats
        self.slotIDByCell = Dictionary(uniqueKeysWithValues: slots.map { ($0.cell, $0.id) })
        self.cellBySlotID = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0.cell) })
        self.ownerByPieceID = Dictionary(uniqueKeysWithValues: pieces.map { ($0.id, $0.owner) })
        self.spare = Dictionary(grouping: pieces, by: \.owner).mapValues { $0.map(\.id) }

        for side in BoardSide.allCases {
            if case .computer(let level) = seats[side] {
                engines[side] = level.engine(forSize: board.size)
            }
        }
    }

    func attach(to game: TabletopGame) {
        self.game = game
        game.addObserver(self)
        republishGaps()
        startIfComputerLeads()
    }

    private func republishGaps() {
        var destinations: [BoardSide: [EquipmentIdentifier]] = [:]
        for side in BoardSide.allCases {
            destinations[side] = legalDestinations(forPieceHeldBy: side)
        }
        gaps.republish(owners: ownerByPieceID, destinations: destinations)
    }

    // MARK: - What the table may do

    /// Slots this side could legally bridge right now.
    ///
    /// Handed to the interaction as `AllowedDestinations.restricted`, so a
    /// bridge simply will not settle anywhere illegal — the rule is felt in the
    /// drag rather than reported after it.
    func legalDestinations(forPieceHeldBy side: BoardSide) -> [EquipmentIdentifier] {
        guard state.current == side, !state.isOver else { return [] }
        return (0..<state.board.cellCount).compactMap { cell in
            guard state.cells[cell] == nil else { return nil }
            return slotIDByCell[cell]
        }
    }

    func side(ofPiece id: EquipmentIdentifier) -> BoardSide? { ownerByPieceID[id] }

    // MARK: - Driving

    private func startIfComputerLeads() {
        if seats[state.current]?.isComputer == true { playComputerTurn() }
    }

    /// The computer answers with the same action a person's drag produces, so a
    /// bridge of its own flies out of its tray and lands on the water.
    private func playComputerTurn() {
        guard !state.isOver,
              let side = Optional(state.current),
              let engine = engines[side],
              let move = engine.chooseMove(in: state, rng: &rng),
              let slotID = slotIDByCell[state.board.index(of: move)],
              let pieceID = spare[side]?.first,
              let game
        else { return }
        game.addAction(.moveEquipment(matching: pieceID, childOf: slotID))
    }

    /// Submits the action a person's drag would produce, for the side whose
    /// turn it is.
    ///
    /// The gaze-and-pinch gesture cannot be driven from a script, so this is how
    /// the rest of the chain — validate, mirror into the engine, hand over the
    /// turn, computer replies — gets exercised without a headset on.
    func simulateDrop() {
        guard !state.isOver,
              let engine = engines[state.current] ?? Difficulty.medium.engine(forSize: state.board.size) as (any Engine)?,
              let move = engine.chooseMove(in: state, rng: &rng),
              let slotID = slotIDByCell[state.board.index(of: move)],
              let pieceID = spare[state.current]?.first,
              let game
        else { return }
        game.addAction(.moveEquipment(matching: pieceID, childOf: slotID))
    }

    private func consume(piece: EquipmentIdentifier, for side: BoardSide) {
        spare[side]?.removeAll { $0 == piece }
    }
}

// MARK: - Observer

extension BridgyRules: TabletopGame.Observer {

    /// `Observer`'s requirements are nonisolated, but TabletopKit drives them
    /// from the main actor along with the rest of the scene. Only the two
    /// identifiers cross the hop — the action itself is generic and would not.
    nonisolated func validateAction(
        _ action: some TabletopAction,
        snapshot: TableSnapshot
    ) -> Bool {
        guard let move = action as? MoveEquipmentAction else { return true }
        let piece = move.equipmentID
        let destination = move.parentID
        return MainActor.assumeIsolated { validate(piece: piece, onto: destination) }
    }

    nonisolated func actionWasConfirmed(
        _ action: some TabletopAction,
        oldSnapshot: TableSnapshot,
        newSnapshot: TableSnapshot
    ) {
        guard let move = action as? MoveEquipmentAction else { return }
        let piece = move.equipmentID
        let destination = move.parentID
        MainActor.assumeIsolated { confirm(piece: piece, onto: destination) }
    }

    private func validate(piece: EquipmentIdentifier, onto destination: EquipmentIdentifier) -> Bool {
        guard let side = ownerByPieceID[piece] else { return true }
        // Anywhere that is not a gap — back to the tray, say — is TabletopKit's
        // business, not the rules'.
        guard let cell = cellBySlotID[destination] else { return true }
        guard !state.isOver, state.current == side else { return false }
        return state.isLegal(state.board.move(at: cell))
    }

    private func confirm(piece: EquipmentIdentifier, onto destination: EquipmentIdentifier) {
        guard let side = ownerByPieceID[piece],
              let cell = cellBySlotID[destination],
              state.current == side,
              state.apply(state.board.move(at: cell))
        else { return }

        consume(piece: piece, for: side)
        republishGaps()
        onChange?(state)

        if seats[state.current]?.isComputer == true, !state.isOver {
            playComputerTurn()
        }
    }
}
#endif
