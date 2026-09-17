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

/// How the board is drawn — on screen and in a shared image.
///
/// This replaces a pair of booleans (`showDots`, `boldLines`) that were really
/// one choice. Joined is the interesting one: the untouched lattice disappears
/// and what is left is the shape of the game.
enum BoardStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case classic
    case connected
    case lines
    case bold
    case neon

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .connected: return "Joined"
        case .lines: return "Lines"
        case .bold: return "Bold"
        case .neon: return "Neon"
        }
    }

    var detail: String {
        switch self {
        case .classic: return "Every dot, as the board really is."
        case .connected: return "Only the dots a bridge has joined."
        case .lines: return "No dots — just the bridges."
        case .bold: return "Thick strokes, no dots. Good for sharing."
        case .neon: return "Glowing strokes on a dark ground."
        }
    }

    enum Dots { case all, connectedOnly, none }

    var dots: Dots {
        switch self {
        case .classic: return .all
        case .connected: return .connectedOnly
        case .lines, .bold, .neon: return .none
        }
    }

    /// Multiplier on the base stroke width.
    var strokeScale: CGFloat {
        switch self {
        case .classic, .connected, .lines: return 1
        case .bold: return 1.7
        case .neon: return 1.15
        }
    }

    var glows: Bool { self == .neon }

    /// Shared images look better on their own ground than on the system's.
    var prefersDarkGround: Bool { self == .neon }
}

extension Player {
    /// What this player is trying to do, in words.
    var goalDescription: String {
        self == .blue ? "top to bottom" : "left to right"
    }

    var displayName: String {
        self == .blue ? "Blue" : "Red"
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
