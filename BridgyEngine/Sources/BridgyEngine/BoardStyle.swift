import CoreGraphics

/// How the board is drawn — on screen and in a shared image.
///
/// This replaces a pair of booleans (`showDots`, `boldLines`) that were really
/// one choice. Joined is the interesting one: the untouched lattice disappears
/// and what is left is the shape of the game.
public enum BoardStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case classic
    case connected
    case lines
    case bold
    case bolder
    case neon

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .connected: return "Joined"
        case .lines: return "Lines"
        case .bold: return "Bold"
        case .bolder: return "Bolder"
        case .neon: return "Neon"
        }
    }

    public var detail: String {
        switch self {
        case .classic: return "Every dot, as the board really is."
        case .connected: return "Only the dots a bridge has joined."
        case .lines: return "No dots — just the bridges."
        case .bold: return "Thick strokes, no dots. Good for sharing."
        case .bolder: return "Wide enough that neighbouring bridges meet."
        case .neon: return "Glowing strokes on a dark ground."
        }
    }

    public enum Dots: Sendable { case all, connectedOnly, none }

    public var dots: Dots {
        switch self {
        case .classic: return .all
        case .connected: return .connectedOnly
        case .lines, .bold, .bolder, .neon: return .none
        }
    }

    /// Stroke width as a fraction of one lattice unit.
    ///
    /// One lattice unit is the closest two parallel bridges ever get: blue's
    /// horizontals sit on even lattice rows and red's on odd ones, so opposite
    /// colours pass within a single unit of each other. A width of exactly `1`
    /// is therefore the point where neighbours meet with no gap at all, and
    /// anything above it overlaps.
    public var strokeLatticeWidth: CGFloat {
        switch self {
        case .classic, .connected, .lines: return 0.34
        case .bold: return 0.58
        case .bolder: return 1
        case .neon: return 0.39
        }
    }

    /// True when a bridge is as wide as the space it has, leaving no room for a
    /// halo around the move just played.
    public var fillsItsCell: Bool { strokeLatticeWidth >= 1 }

    public var glows: Bool { self == .neon }

    /// Shared images look better on their own ground than on the system's.
    public var prefersDarkGround: Bool { self == .neon }
}
