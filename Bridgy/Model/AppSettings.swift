import Foundation
import Observation
import SwiftUI

/// User preferences, persisted to `UserDefaults`.
@MainActor
@Observable
final class AppSettings {

    var backdrop: Backdrop { didSet { store(backdrop.rawValue, "backdrop") } }
    var colorway: Colorway { didSet { store(colorway.rawValue, "colorway") } }
    var soundEnabled: Bool { didSet { store(soundEnabled, "soundEnabled") } }
    var hapticsEnabled: Bool { didSet { store(hapticsEnabled, "hapticsEnabled") } }
    var showDots: Bool { didSet { store(showDots, "showDots") } }
    var boldLines: Bool { didSet { store(boldLines, "boldLines") } }
    var showHints: Bool { didSet { store(showHints, "showHints") } }
    var watchSpeed: WatchSpeed { didSet { store(watchSpeed.rawValue, "watchSpeed") } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        backdrop = Backdrop(rawValue: defaults.string(forKey: "backdrop") ?? "") ?? .midnight
        colorway = Colorway(rawValue: defaults.string(forKey: "colorway") ?? "") ?? .classic
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        showDots = defaults.object(forKey: "showDots") as? Bool ?? true
        boldLines = defaults.object(forKey: "boldLines") as? Bool ?? false
        showHints = defaults.object(forKey: "showHints") as? Bool ?? false
        watchSpeed = WatchSpeed(rawValue: defaults.string(forKey: "watchSpeed") ?? "") ?? .normal
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
