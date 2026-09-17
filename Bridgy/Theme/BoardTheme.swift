import BridgyEngine
import Foundation
import SwiftUI

/// A pair of player colours.
///
/// Blue and red are the original's, kept because that is what the game is
/// remembered in. Red on blue is also the single most common form of colour
/// blindness to run into, so Contrast exists: the Okabe-Ito pairing, which stays
/// distinguishable under every common type.
enum BoardTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case classic
    case contrast
    case ocean
    case sunset
    case orchid
    case ember

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .contrast: return "Contrast"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .orchid: return "Orchid"
        case .ember: return "Ember"
        }
    }

    private var hexes: (blue: String, red: String) {
        switch self {
        case .classic: return ("6DAEEB", "FF2539")
        case .contrast: return ("56B4E9", "E69F00")
        case .ocean: return ("2EC4B6", "EF476F")
        case .sunset: return ("118AB2", "F78C6B")
        case .orchid: return ("7B6CF6", "06D6A0")
        case .ember: return ("8ECAE6", "FB8500")
        }
    }

    func color(for player: Player) -> Color {
        Color(hex: player == .blue ? hexes.blue : hexes.red)
    }

    /// True where the pairing survives the common colour-vision deficiencies.
    var isColorVisionFriendly: Bool {
        switch self {
        case .contrast, .ocean, .ember: return true
        case .classic, .sunset, .orchid: return false
        }
    }
}

extension Player {
    /// Named for what the player is trying to do rather than for a colour.
    ///
    /// A theme can make the second player orange or pink, at which point "Red"
    /// is simply false — but Across is always across, and the direction is the
    /// thing worth remembering anyway. The colour still travels with the label
    /// as a dot.
    var displayName: String {
        self == .blue ? "Down" : "Across"
    }

    /// The same idea spelled out, for places that are teaching rather than
    /// labelling.
    var goalDescription: String {
        self == .blue ? "top to bottom" : "left to right"
    }

    var symbolName: String {
        self == .blue ? "arrow.up.and.down" : "arrow.left.and.right"
    }
}

extension Color {
    /// `RRGGBB`, the form the palettes are written in.
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
