import BridgyEngine
import Foundation
import Observation
import SwiftUI

/// User preferences, persisted to `UserDefaults`.
@MainActor
@Observable
final class AppSettings {

    var theme: BoardTheme { didSet { store(theme.rawValue, "boardTheme") } }
    var boardStyle: BoardStyle { didSet { store(boardStyle.rawValue, "boardStyle") } }
    var bridgeCap: BridgeCap { didSet { store(bridgeCap.rawValue, "bridgeCap") } }
    var soundEnabled: Bool { didSet { store(soundEnabled, "soundEnabled") } }
    var hapticsEnabled: Bool { didSet { store(hapticsEnabled, "hapticsEnabled") } }
    var showHints: Bool { didSet { store(showHints, "showHints") } }
    var highlightsWinningPath: Bool { didSet { store(highlightsWinningPath, "highlightsWinningPath") } }
    var hasSeenWelcome: Bool { didSet { store(hasSeenWelcome, "hasSeenWelcome") } }
    /// The "ask Siri for a move" tip under the board, until it is closed.
    var showsSiriHintTip: Bool { didSet { store(showsSiriHintTip, "showsSiriHintTip") } }

    var watchPace: WatchPace {
        didSet {
            store(watchPace.movesPerSecond, "watchMovesPerSecond")
            store(watchPace.allowsFullThinking, "watchAllowsFullThinking")
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // `colorway` was the old two-option setting; carry a choice over rather
        // than silently resetting it.
        let storedTheme = defaults.string(forKey: "boardTheme")
            ?? defaults.string(forKey: "colorway").map { $0 == "accessible" ? "contrast" : $0 }
        theme = BoardTheme(rawValue: storedTheme ?? "") ?? .classic

        // Likewise `showDots` and `boldLines`, which were really one choice.
        if let storedStyle = defaults.string(forKey: "boardStyle"),
           let style = BoardStyle(rawValue: storedStyle) {
            boardStyle = style
        } else if defaults.object(forKey: "showDots") as? Bool == false {
            boardStyle = .lines
        } else if defaults.object(forKey: "boldLines") as? Bool == true {
            boardStyle = .bold
        } else {
            boardStyle = .classic
        }

        bridgeCap = BridgeCap(rawValue: defaults.string(forKey: "bridgeCap") ?? "") ?? .rounded

        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        showHints = defaults.object(forKey: "showHints") as? Bool ?? false
        highlightsWinningPath = defaults.object(forKey: "highlightsWinningPath") as? Bool ?? true
        hasSeenWelcome = defaults.object(forKey: "hasSeenWelcome") as? Bool ?? false
        showsSiriHintTip = defaults.object(forKey: "showsSiriHintTip") as? Bool ?? true
        watchPace = WatchPace(
            movesPerSecond: defaults.object(forKey: "watchMovesPerSecond") as? Double
                ?? WatchPace.default.movesPerSecond,
            allowsFullThinking: defaults.object(forKey: "watchAllowsFullThinking") as? Bool
                ?? WatchPace.default.allowsFullThinking
        )
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}

extension EnvironmentValues {
    /// Roughly how many points the board has to draw itself in, measured once at
    /// the root. Drives the comfortable board-size cap.
    @Entry var availableBoardSide: CGFloat = 360
}
