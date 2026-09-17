import SwiftUI

/// The gradient behind everything.
///
/// The original painted a fixed `background.png` behind every panel. Liquid
/// Glass needs something with colour and movement underneath it to refract, so
/// the bitmap is replaced by a small set of gradients the player chooses from.
enum Backdrop: String, CaseIterable, Identifiable, Codable, Sendable {
    case midnight
    case aurora
    case ember
    case slate
    case mono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .midnight: return "Midnight"
        case .aurora: return "Aurora"
        case .ember: return "Ember"
        case .slate: return "Slate"
        case .mono: return "Mono"
        }
    }

    /// Nine colours on a 3x3 mesh, dark variant first.
    private var palette: (dark: [Color], light: [Color]) {
        switch self {
        case .midnight:
            return (
                dark: hexes(["0B1220", "12203A", "0B1220",
                             "17375E", "1E4D7B", "132B49",
                             "0A1020", "102037", "070C16"]),
                light: hexes(["DCE8F7", "C6DCF4", "DCE8F7",
                              "AECDEE", "93BCE8", "B6D2F0",
                              "E8F1FB", "CFE1F6", "EEF5FC"])
            )
        case .aurora:
            return (
                dark: hexes(["07131A", "0B2A2E", "07131A",
                             "0F3D3A", "16614F", "103A44",
                             "061019", "0A2430", "050C12"]),
                light: hexes(["DDF3EE", "BFE9DC", "DDF3EE",
                              "9FDCC8", "7FCDB6", "A8E0D6",
                              "ECFAF6", "CCEFE4", "F2FBF8"])
            )
        case .ember:
            return (
                dark: hexes(["1A0B0B", "2E1310", "1A0B0B",
                             "5A2318", "7C3A1C", "441C14",
                             "140808", "2A120E", "0E0505"]),
                light: hexes(["FBE8DF", "F7D3C1", "FBE8DF",
                              "F0B999", "E8A279", "F4C7AC",
                              "FDF1EA", "F9DECD", "FEF6F1"])
            )
        case .slate:
            return (
                dark: hexes(["101215", "1A1E24", "101215",
                             "252B33", "31383F", "1F242B",
                             "0C0E11", "171A1F", "090A0C"]),
                light: hexes(["E9EBEE", "D8DCE2", "E9EBEE",
                              "C4CAD2", "B2B9C2", "CED4DA",
                              "F2F4F6", "E0E3E8", "F7F8F9"])
            )
        case .mono:
            return (
                dark: hexes(["000000", "0A0A0A", "000000",
                             "141414", "1C1C1C", "101010",
                             "000000", "080808", "000000"]),
                light: hexes(["FFFFFF", "F5F5F5", "FFFFFF",
                              "ECECEC", "E4E4E4", "F0F0F0",
                              "FFFFFF", "F8F8F8", "FFFFFF"])
            )
        }
    }

    func colors(for scheme: ColorScheme) -> [Color] {
        scheme == .dark ? palette.dark : palette.light
    }

    /// A two-colour reduction, for swatches and for anywhere a mesh is overkill.
    func swatch(for scheme: ColorScheme) -> [Color] {
        let all = colors(for: scheme)
        return [all[4], all[0]]
    }

    private func hexes(_ values: [String]) -> [Color] {
        values.map(Color.init(hex:))
    }
}

/// Fills the whole window with the chosen backdrop.
struct BackdropView: View {
    let backdrop: Backdrop
    @Environment(\.colorScheme) private var scheme

    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.5, 0.5], [1, 0.5],
        [0, 1], [0.5, 1], [1, 1]
    ]

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: Self.points,
            colors: backdrop.colors(for: scheme)
        )
        .ignoresSafeArea()
    }
}

extension Color {
    /// `RRGGBB`, the form the palettes above are written in.
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
