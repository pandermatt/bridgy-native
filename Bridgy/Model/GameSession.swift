import BridgyEngine
import Foundation
import Observation

/// Drives one game: holds the position, runs the computer's turns off the main
/// actor, and keeps the saved snapshot up to date.
///
/// Most of the care here is about what *does not* happen on the main thread.
/// Watch mode can ask for fifteen moves a second, and at that rate anything
/// per-move that touches the main actor — a graph rebuild, a JSON encode, a disk
/// write — stops being invisible and starts being the frame budget.
@MainActor
@Observable
final class GameSession {

    /// Moves each player still needs, computed off the main actor and cached.
    ///
    /// This used to be called straight from the view body, which meant a full
    /// graph build and breadth-first search per player per render.
    struct Readout: Sendable, Equatable {
        var blue: Int?
        var red: Int?
        var isStale = true
    }

    /// Any change to the position ends a review of an earlier one.
    private(set) var state: GameState {
        didSet { if reviewIndex != nil { reviewIndex = nil } }
    }
    /// An earlier position being looked at, counted in moves; nil is live.
    var reviewIndex: Int?
    private(set) var configuration: GameConfiguration
    private(set) var isThinking = false
    private(set) var isPaused = false
    private(set) var readout = Readout()
    /// Set when the game ends or is stopped, so the screen can react once.
    private(set) var hasFinished = false
    /// Cells of the chain that won. Computed once, when the game is decided —
    /// the board redraws far too often to search for it per frame.
    private(set) var winningPath: Set<Int>?

    /// A suggested move, shown until the player does something else.
    var hintMove: Move?

    private let settings: AppSettings
    private let sound: SoundGenerator
    private let store: GameStore

    /// Built once per game: these depend only on the board, never the position.
    private let blueGraph: PlayerGraph
    private let redGraph: PlayerGraph

    private var thinkingTask: Task<Void, Never>?
    private var readoutTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var paceTask: Task<Void, Never>?

    /// Cached engines, keyed so a pace change rebuilds only what depends on it.
    private struct EngineKey: Hashable {
        let difficulty: Difficulty
        let size: Int
        let budgetMilliseconds: Int
    }
    private var engineCache: [EngineKey: any Engine] = [:]

    /// Timestamps of recent moves, for reporting the rate actually achieved.
    private var recentMoves: [ContinuousClock.Instant] = []

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
        let position = state ?? GameState(size: configuration.size)
        self.state = position
        self.blueGraph = PlayerGraph(board: position.board, player: .blue)
        self.redGraph = PlayerGraph(board: position.board, player: .red)
    }

    // MARK: - Status

    var board: Board { state.board }
    var currentSeat: Seat { configuration.seat(for: state.current) }

    var isHumanTurn: Bool {
        !state.isOver && !currentSeat.isComputer
    }

    var canUndo: Bool {
        guard !configuration.isWatchOnly else { return false }
        return state.canUndo
    }

    /// The rate the game is actually managing, when it falls short of the ask.
    var achievedMovesPerSecond: Double? {
        guard configuration.isWatchOnly, recentMoves.count >= 3 else { return nil }
        guard let first = recentMoves.first, let last = recentMoves.last else { return nil }
        let span = last - first
        let seconds = Double(span.components.seconds)
            + Double(span.components.attoseconds) / 1e18
        guard seconds > 0 else { return nil }
        return Double(recentMoves.count - 1) / seconds
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

    /// Suggests what a strong engine would play here, and shows it on the board.
    func requestHint() {
        guard isHumanTurn else { return }
        let snapshot = state
        Task { [weak self] in
            let move = await Self.think(
                engine: ShortestPathEngine(strategy: .balanced, tieBreak: .disturbOpponent),
                state: snapshot,
                seed: UInt64.random(in: .min ... .max)
            )
            guard let self, !Task.isCancelled else { return }
            self.hintMove = move
        }
    }

    // MARK: - Playing

    func begin() {
        guard !isPaused else { return }
        refreshReadout()
        advance()
    }

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
            state.undo(untilTurnOf: human)
        } else {
            state.undo()
        }
        hasFinished = false
        winningPath = nil
        refreshReadout()
        scheduleSave()
        advance()
    }

    func restart() {
        cancelThinking()
        sound.stopAll()
        state = GameState(size: configuration.size)
        hintMove = nil
        isPaused = false
        hasFinished = false
        winningPath = nil
        recentMoves.removeAll()
        refreshReadout()
        scheduleSave()
        advance()
    }

    /// Pause and resume, for two computers playing each other.
    func togglePause() {
        isPaused.toggle()
        if isPaused {
            cancelThinking()
            sound.stopAll()
        } else {
            advance()
        }
    }

    /// Ends the game for good — the Stop button. The caller returns to setup.
    func finish() {
        cancelThinking()
        sound.stopAll()
        hasFinished = true
        store.clear()
    }

    /// Leaving the Play tab: stop working and latch paused, so nothing carries
    /// on thinking or sounding in the background while another tab is up. The
    /// game itself is kept, and comes back as Continue.
    func suspend() {
        isPaused = true
        stop()
    }

    /// Leaving the screen: stop working, but keep the game.
    func stop() {
        cancelThinking()
        sound.stopAll()
        flushSave()
    }

    /// The pace changed. Debounced, because this is wired to a slider and the
    /// old code restarted the engine on every tick of a drag.
    func paceChanged() {
        guard configuration.isWatchOnly, !isPaused, !state.isOver else { return }
        paceTask?.cancel()
        paceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            self.advance()
        }
    }

    // MARK: - Internals

    private func commit(_ move: Move) {
        let index = state.moveCount
        guard state.apply(move) else { return }
        hintMove = nil

        recentMoves.append(ContinuousClock().now)
        if recentMoves.count > 12 { recentMoves.removeFirst() }

        if settings.soundEnabled {
            if state.isOver {
                sound.playWin()
            } else {
                sound.playMove(index: index, pace: pace)
            }
        }
        if state.isOver {
            hasFinished = true
            captureWinningPath()
            store.clear()
        } else {
            scheduleSave()
        }
        refreshReadout()
        advance()
    }

    /// Reuses the graph already built for this game rather than making another.
    private func captureWinningPath() {
        guard let winner = state.winner else { winningPath = nil; return }
        let graph = winner == .blue ? blueGraph : redGraph
        winningPath = Set(WinningPath.cells(in: state, for: winner, graph: graph))
    }

    private var pace: WatchPace? {
        configuration.isWatchOnly ? settings.watchPace : nil
    }

    /// Hands over to an engine when it is a computer's turn.
    private func advance() {
        cancelThinking()
        guard !state.isOver else { return }
        guard case .computer(let level) = configuration.seat(for: state.current) else { return }
        guard !configuration.isWatchOnly || !isPaused else { return }

        let watching = configuration.isWatchOnly
        let budget = pace?.thinkingBudget

        if watching, pace?.isInstant == true,
           case .computer(let blueLevel) = configuration.blue,
           case .computer(let redLevel) = configuration.red {
            playInstantly(
                blue: engine(for: blueLevel, budget: budget),
                red: engine(for: redLevel, budget: budget)
            )
            return
        }
        let engine = engine(for: level, budget: budget)
        let snapshot = state
        // A beat before a computer move, so its reply does not land in the same
        // instant as the tap that caused it. When watching, the beat is the pace.
        let beat = watching ? (pace?.interval ?? .milliseconds(220)) : .milliseconds(220)
        let seed = UInt64.random(in: .min ... .max)

        // Only worth publishing when someone is waiting on it; in watch mode it
        // is always true and would just be two extra invalidations per move.
        if !watching { isThinking = true }

        thinkingTask = Task { [weak self] in
            // `think` is nonisolated, so this hops off the main actor — and stays
            // in the same task, so cancelling actually stops the search.
            async let searched = Self.think(engine: engine, state: snapshot, seed: seed)
            if beat > .zero { try? await Task.sleep(for: beat) }
            let chosen = await searched
            guard let self, !Task.isCancelled else { return }
            if !watching { self.isThinking = false }
            guard let chosen, self.state.isLegal(chosen) else { return }
            self.commit(chosen)
        }
    }

    // MARK: - Instant

    /// Plays as fast as the engines allow, a frame's worth of moves at a time.
    ///
    /// With no pause, one SwiftUI update per move becomes the limit: a random
    /// 35×35 game is over two thousand redraws of a board that is itself two
    /// thousand cells. So moves are played off the main actor for about one
    /// frame, then committed together, and the board redraws once per batch.
    private func playInstantly(blue: any Engine, red: any Engine) {
        let snapshot = state
        let seed = UInt64.random(in: .min ... .max)
        thinkingTask = Task { [weak self] in
            let batch = await Self.playBatch(blue: blue, red: red, state: snapshot, seed: seed)
            guard let self, !Task.isCancelled, !batch.isEmpty else { return }
            self.commitBatch(batch)
        }
    }

    private nonisolated static func playBatch(
        blue: any Engine,
        red: any Engine,
        state: GameState,
        seed: UInt64,
        frame: Duration = .milliseconds(14)
    ) async -> [Move] {
        var rng = SeededRandomNumberGenerator(seed: seed)
        var working = state
        var played: [Move] = []
        let deadline = ContinuousClock.now + frame
        repeat {
            let engine: any Engine = working.current == .blue ? blue : red
            guard !Task.isCancelled,
                  let move = engine.chooseMove(in: working, rng: &rng),
                  working.apply(move)
            else { break }
            played.append(move)
        } while !working.isOver && ContinuousClock.now < deadline
        return played
    }

    private func commitBatch(_ moves: [Move]) {
        for move in moves where !state.isOver {
            guard state.apply(move) else { break }
        }
        hintMove = nil
        if state.isOver {
            if settings.soundEnabled { sound.playWin() }
            hasFinished = true
            captureWinningPath()
            store.clear()
        } else {
            scheduleSave()
        }
        refreshReadout()
        advance()
    }

    /// Runs the search off the main actor, inside the caller's task so that
    /// cancellation reaches it.
    private nonisolated static func think(
        engine: any Engine,
        state: GameState,
        seed: UInt64
    ) async -> Move? {
        var rng = SeededRandomNumberGenerator(seed: seed)
        return engine.chooseMove(in: state, rng: &rng)
    }

    /// Engines are reused across turns. It matters: `PerfectEngine` carries its
    /// pairing strategy internally, and rebuilding it would throw that away and
    /// force a full spanning-tree pack on the next move.
    private func engine(for level: Difficulty, budget: Duration?) -> any Engine {
        let key = EngineKey(
            difficulty: level,
            size: state.board.size,
            budgetMilliseconds: budget.map { Int($0.components.seconds * 1000 + $0.components.attoseconds / 1_000_000_000_000_000) } ?? -1
        )
        if let cached = engineCache[key] { return cached }
        let made = level.engine(forSize: state.board.size, thinkingBudget: budget)
        engineCache[key] = made
        return made
    }

    private func cancelThinking() {
        thinkingTask?.cancel()
        thinkingTask = nil
        paceTask?.cancel()
        paceTask = nil
        isThinking = false
    }

    // MARK: - Readout

    /// Recomputes the moves-to-win figures off the main actor, coalescing bursts
    /// so a fast watch game does not queue one search per move.
    private func refreshReadout() {
        readoutTask?.cancel()
        guard settings.showHints || !configuration.isWatchOnly else {
            readout = Readout()
            return
        }
        let snapshot = state
        let blue = blueGraph
        let red = redGraph
        readout.isStale = true
        readoutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let value = await Self.computeReadout(state: snapshot, blue: blue, red: red)
            guard let self, !Task.isCancelled else { return }
            self.readout = value
        }
    }

    private nonisolated static func computeReadout(
        state: GameState,
        blue: PlayerGraph,
        red: PlayerGraph
    ) async -> Readout {
        Readout(
            blue: ShortestPath.distance(in: state, for: .blue, graph: blue),
            red: ShortestPath.distance(in: state, for: .red, graph: red),
            isStale: false
        )
    }

    // MARK: - Saving

    /// At most one write a second. This used to JSON-encode the whole position,
    /// union-find structures and all, and write it to disk on every single move.
    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            self.saveTask = nil
            self.flushSave()
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        guard !state.isOver, state.moveCount > 0 else {
            store.clear()
            return
        }
        let snapshot = GameStore.Snapshot(configuration: configuration, state: state)
        let store = self.store
        Task.detached(priority: .utility) {
            store.save(snapshot)
        }
    }
}
