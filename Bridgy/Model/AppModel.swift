import BridgyEngine
import Observation
import SwiftUI

/// App-wide state: preferences, audio, and the game in progress.
@MainActor
@Observable
final class AppModel {

    let settings = AppSettings()
    let sound = SoundGenerator()
    /// Victory-song previews; one player for the whole app.
    let audio = AudioEngine()
    let store = GameStore()
    let agents = AgentStore()
    /// Lives here rather than on its screen so training carries on while you
    /// look at something else.
    let training = TrainingRun()
    /// Also here, so experiments keep running — and their results stay —
    /// while you switch to another part of the app.
    let library = ExperimentLibrary()
    /// Finished games from Play, for replay and recap.
    let history = PlayHistory()
    let runner = ExperimentRunner()

    /// Set by an intent to bring a part of the app forward; the root clears it.
    var requestedTab: AppTab?
    /// Set by an intent to open an experiment in the Lab; the Lab clears it.
    var openExperiment: UUID?

    /// The live game, if one is on screen.
    var session: GameSession?
    /// A saved game that can be picked up again.
    private(set) var resumable: GameStore.Snapshot?

    /// Last setup used, so New Game opens where you left off.
    var configuration: GameConfiguration = .default

    init() {
        resumable = store.load()
        if let resumable { configuration = resumable.configuration }
    }

    /// Plays a saved agent in a game: its network with its own search depth.
    func agentEngine(_ id: UUID) -> (any Engine)? {
        guard let agent = agents.agents.first(where: { $0.id == id }),
              let network = agents.network(for: agent) else { return nil }
        return NeuralMCTSEngine(network: network, simulations: agent.parameters.simulations, name: agent.name)
    }

    func prepareAudio() {
        guard settings.soundEnabled else { return }
        sound.prepare()
    }

    /// Starts a fresh game and makes it the live session.
    @discardableResult
    func startGame(_ configuration: GameConfiguration) -> GameSession {
        self.configuration = configuration
        session?.stop()
        let session = GameSession(
            configuration: configuration,
            settings: settings,
            sound: sound,
            store: store,
            agentEngine: agentEngine
        )
        self.session = session
        resumable = nil
        return session
    }

    /// Picks up the saved game, if there is one.
    @discardableResult
    func resumeGame() -> GameSession? {
        guard let snapshot = resumable else { return nil }
        session?.stop()
        let session = GameSession(
            configuration: snapshot.configuration,
            settings: settings,
            sound: sound,
            store: store,
            state: snapshot.state,
            agentEngine: agentEngine
        )
        self.session = session
        self.configuration = snapshot.configuration
        resumable = nil
        return session
    }

    /// Leaving Play: park the live game. The tab comes back to setup, and the
    /// game is offered there as Continue rather than resuming mid-move under
    /// someone who went to look at Settings.
    func parkSession() {
        guard let session else { return }
        session.suspend()
        self.session = nil
        resumable = store.load()
    }

    func refreshResumable() {
        guard session == nil else { return }
        resumable = store.load()
    }

    var canResume: Bool { resumable != nil }

    // MARK: - The table (Vision Pro)

    /// The game while it is being played on the table in the room: where it
    /// started and every move since. Nil when there is no table open.
    ///
    /// One game, two places. The window's session is parked while the table
    /// has it — two engines answering the same position would each play a
    /// move — and every move on the table is saved, so the window picks up
    /// exactly where the table left off.
    var tableGame: GameStore.Snapshot? {
        // A new game on the table, or Play Again there, is a new game.
        didSet { if tableGame?.state.moveCount == 0 || oldValue == nil { tableGameID = UUID() } }
    }
    private var tableGameID = UUID()

    /// Hands the game in the window to the table, as it stands.
    func moveGameToTable() {
        let snapshot = session.map { GameStore.Snapshot(configuration: $0.configuration, state: $0.state) }
            ?? resumable
            ?? GameStore.Snapshot(configuration: configuration, state: GameState(size: configuration.size))
        parkSession()
        tableGame = snapshot
    }

    /// A new game, straight onto the table.
    func startTableGame(_ configuration: GameConfiguration) {
        parkSession()
        self.configuration = configuration
        tableGame = GameStore.Snapshot(configuration: configuration, state: GameState(size: configuration.size))
    }

    /// A move on the table, or a new game started there.
    func tableDidChange(_ state: GameState) {
        guard var snapshot = tableGame else { return }
        snapshot.state = state
        tableGame = snapshot
        store.save(snapshot)
        if state.isOver { history.record(state, configuration: snapshot.configuration, source: tableGameID) }
    }

    /// The table is closed: the game comes back to the window, where it was.
    func tableDidClose() {
        guard tableGame != nil else { return }
        tableGame = nil
        resumable = store.load()
        resumeGame()
    }
}
