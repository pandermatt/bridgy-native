import BridgyEngine
import Observation
import SwiftUI

/// Where the app can navigate.
enum Destination: String, Hashable, Identifiable, CaseIterable {
    case play
    case watch
    case tournament
    case howToPlay
    case settings
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .play: return "Play"
        case .watch: return "Watch"
        case .tournament: return "Tournament"
        case .howToPlay: return "How to Play"
        case .settings: return "Settings"
        case .about: return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .play: return "play.circle"
        case .watch: return "cpu"
        case .tournament: return "trophy"
        case .howToPlay: return "questionmark.circle"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .play: return "Against the computer, or side by side"
        case .watch: return "Let two engines play it out"
        case .tournament: return "Every engine against every other"
        case .howToPlay: return "The rules, in a minute"
        case .settings: return "Colours, sound, and the board"
        case .about: return "Gale, Gross, and a solved game"
        }
    }
}

/// App-wide state: preferences, audio, and the game in progress.
@MainActor
@Observable
final class AppModel {

    let settings = AppSettings()
    let sound = SoundGenerator()
    let store = GameStore()

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
            store: store
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
            state: snapshot.state
        )
        self.session = session
        self.configuration = snapshot.configuration
        resumable = nil
        return session
    }

    func refreshResumable() {
        guard session == nil else { return }
        resumable = store.load()
    }

    var canResume: Bool { resumable != nil }
}
