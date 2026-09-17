import BridgyEngine
import Foundation
import Observation

/// Drives one game: holds the position, runs the computer's turns off the main
/// actor, and keeps the saved snapshot up to date.
@MainActor
@Observable
final class GameSession {

    private(set) var state: GameState
    private(set) var configuration: GameConfiguration
    /// True while an engine is searching, so the UI can say so.
    private(set) var isThinking = false
    /// Set when two computers are playing and the player has paused them.
    private(set) var isPaused = false

    /// Dot the player has tapped, waiting for a second tap to complete an edge.
    var selectedDot: BoardGeometry.Dot?
    /// Live drag, for the rubber-band preview.
    var dragOrigin: BoardGeometry.Dot?
    var dragPoint: CGPoint?
    /// A suggested move, shown until the player does something else.
    var hintMove: Move?

    private var thinkingTask: Task<Void, Never>?
    private let settings: AppSettings
    private let sound: SoundGenerator
    private let store: GameStore

    init(
        configuration: GameConfiguration,
        settings: AppSettings,
        sound: SoundGenerator,
        store: GameStore = GameStore(),
        state: GameState? = nil
    ) {
        self.configuration = configuration
        self.settings = settings
        self.sound = sound
        self.store = store
        self.state = state ?? GameState(size: configuration.size)
        self.isPaused = false
    }

    // MARK: - Status

    var board: Board { state.board }
    var currentSeat: Seat { configuration.seat(for: state.current) }

    /// Whether the person holding the device may move right now.
    var isHumanTurn: Bool {
        !state.isOver && !currentSeat.isComputer
    }

    var canUndo: Bool {
        guard !configuration.isWatchOnly else { return false }
        return state.canUndo
    }

    /// Moves the given player still needs, for the hint readout.
    func movesToWin(for player: Player) -> Int? {
        ShortestPath.movesToWin(in: state, for: player)
    }

    /// Suggests what a strong engine would play here, and shows it on the board.
    func requestHint() {
        guard isHumanTurn else { return }
        var rng = SeededRandomNumberGenerator()
        hintMove = ShortestPathEngine(strategy: .balanced, tieBreak: .disturbOpponent)
            .chooseMove(in: state, rng: &rng)
    }

    var statusText: String {
        if let winner = state.winner {
            return "\(winner.displayName) wins"
        }
        if configuration.isWatchOnly {
            guard !isPaused else { return "Paused" }
            return "\(state.current.displayName) · \(currentSeat.displayName)"
        }
        if isThinking { return "\(currentSeat.displayName) is thinking…" }
        if configuration.isLocalTwoPlayer { return "\(state.current.displayName) to play" }
        if isHumanTurn { return "Your turn — \(state.current.goalDescription)" }
        return "\(currentSeat.displayName) is playing \(state.current.displayName)"
    }

    // MARK: - Playing

    /// Starts or resumes the game, handing over to an engine if it is its turn.
    func begin() {
        guard !configuration.isWatchOnly || !isPaused else { return }
        advance()
    }

    /// Plays a move on behalf of the person. Returns false if it was not legal.
    @discardableResult
    func play(_ move: Move) -> Bool {
        guard isHumanTurn, state.isLegal(move) else { return false }
        commit(move)
        return true
    }

    func undo() {
        guard canUndo else { return }
        cancelThinking()
        if let human = configuration.soloHumanPlayer {
            // Step back past the computer's reply so the turn returns to the player.
            state.undo(untilTurnOf: human)
        } else {
            state.undo()
        }
        persist()
        advance()
    }

    func restart() {
        cancelThinking()
        state = GameState(size: configuration.size)
        selectedDot = nil
        dragOrigin = nil
        dragPoint = nil
        hintMove = nil
        isPaused = false
        persist()
        advance()
    }

    /// Pause and resume, for two computers playing each other.
    func togglePause() {
        isPaused.toggle()
        if isPaused {
            cancelThinking()
        } else {
            advance()
        }
    }

    func stop() {
        cancelThinking()
    }

    /// Picks up a new speed straight away instead of after the move in flight.
    func paceChanged() {
        guard configuration.isWatchOnly, !isPaused, !state.isOver else { return }
        advance()
    }

    // MARK: - Internals

    private func commit(_ move: Move) {
        let index = state.moveCount
        guard state.apply(move) else { return }
        selectedDot = nil
        dragOrigin = nil
        dragPoint = nil
        hintMove = nil
        if settings.soundEnabled {
            if state.isOver { sound.playWin() } else { sound.playMove(index: index) }
        }
        persist()
        advance()
    }

    /// Hands over to an engine when it is a computer's turn.
    private func advance() {
        cancelThinking()
        guard !state.isOver else {
            store.clear()
            return
        }
        guard case .computer(let level) = configuration.seat(for: state.current) else { return }
        guard !configuration.isWatchOnly || !isPaused else { return }

        let watching = configuration.isWatchOnly
        let pace = settings.watchPace
        let engine = level.engine(
            forSize: state.board.size,
            thinkingBudget: watching ? pace.thinkingBudget : nil
        )
        let snapshot = state
        // A pause before a computer move, so its reply does not appear to happen
        // in the same instant as the tap that triggered it. When watching, the
        // pause *is* the requested pace.
        let pause = watching ? pace.interval : .milliseconds(220)

        isThinking = true
        thinkingTask = Task { [weak self] in
            let search = Task.detached(priority: .userInitiated) { () -> Move? in
                var rng = SeededRandomNumberGenerator()
                return engine.chooseMove(in: snapshot, rng: &rng)
            }
            if pause > .zero { try? await Task.sleep(for: pause) }
            let chosen = await search.value
            guard let self, !Task.isCancelled else { return }
            self.isThinking = false
            guard let chosen, self.state.isLegal(chosen) else { return }
            self.commit(chosen)
        }
    }

    private func cancelThinking() {
        thinkingTask?.cancel()
        thinkingTask = nil
        isThinking = false
    }

    private func persist() {
        guard !state.isOver, state.moveCount > 0 else {
            store.clear()
            return
        }
        store.save(GameStore.Snapshot(configuration: configuration, state: state))
    }
}
