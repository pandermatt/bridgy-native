import Foundation
import Observation
import SwiftUI

/// User preferences, persisted to `UserDefaults`.
@MainActor
@Observable
final class AppSettings {

    var colorway: Colorway { didSet { store(colorway.rawValue, "colorway") } }
    var soundEnabled: Bool { didSet { store(soundEnabled, "soundEnabled") } }
    var hapticsEnabled: Bool { didSet { store(hapticsEnabled, "hapticsEnabled") } }
    var showDots: Bool { didSet { store(showDots, "showDots") } }
    var boldLines: Bool { didSet { store(boldLines, "boldLines") } }
    var showHints: Bool { didSet { store(showHints, "showHints") } }

    var watchPace: WatchPace {
        didSet {
            store(watchPace.movesPerSecond, "watchMovesPerSecond")
            store(watchPace.allowsFullThinking, "watchAllowsFullThinking")
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        colorway = Colorway(rawValue: defaults.string(forKey: "colorway") ?? "") ?? .classic
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        showDots = defaults.object(forKey: "showDots") as? Bool ?? true
        boldLines = defaults.object(forKey: "boldLines") as? Bool ?? false
        showHints = defaults.object(forKey: "showHints") as? Bool ?? false
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
