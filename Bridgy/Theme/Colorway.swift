import BridgyEngine
import SwiftUI

/// The two player colours.
///
/// Blue and red are the original's, kept because they are what the game is
/// remembered in. Red on blue is the single most common form of colour blindness
/// to run into, though, so there is an alternative that swaps red for orange —
/// the Okabe-Ito pairing, which stays distinguishable under every common type.
enum Colorway: String, CaseIterable, Identifiable, Codable, Sendable {
    case classic
    case accessible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .accessible: return "High contrast"
        }
    }

    var detail: String {
        switch self {
        case .classic: return "Blue and red, as the original."
        case .accessible: return "Blue and orange, distinguishable with colour vision deficiency."
        }
    }

    func color(for player: Player) -> Color {
        switch (self, player) {
        case (.classic, .blue): return Color(hex: "6DAEEB")
        case (.classic, .red): return Color(hex: "FF2539")
        case (.accessible, .blue): return Color(hex: "56B4E9")
        case (.accessible, .red): return Color(hex: "E69F00")
        }
    }
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
