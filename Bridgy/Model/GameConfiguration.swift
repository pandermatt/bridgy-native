import BridgyEngine
import Foundation

/// Who is sitting in a seat.
enum Seat: Hashable, Codable, Sendable {
    case human
    case computer(Difficulty)

    var isComputer: Bool {
        if case .computer = self { return true }
        return false
    }

    var difficulty: Difficulty? {
        if case .computer(let level) = self { return level }
        return nil
    }

    var displayName: String {
        switch self {
        case .human: return "You"
        case .computer(let level): return level.displayName
        }
    }

    var symbolName: String {
        switch self {
        case .human: return "person"
        case .computer(let level): return level.symbolName
        }
    }
}

/// Everything needed to start a game.
struct GameConfiguration: Hashable, Codable, Sendable {
    var size: Int
    var blue: Seat
    var red: Seat

    static let `default` = GameConfiguration(size: 6, blue: .human, red: .computer(.medium))

    func seat(for player: Player) -> Seat {
        player == .blue ? blue : red
    }

    var isWatchOnly: Bool { blue.isComputer && red.isComputer }
    var isLocalTwoPlayer: Bool { !blue.isComputer && !red.isComputer }

    /// The human's colour, when exactly one seat is human.
    var soloHumanPlayer: Player? {
        switch (blue.isComputer, red.isComputer) {
        case (false, true): return .blue
        case (true, false): return .red
        default: return nil
        }
    }

    var summary: String {
        "\(blue.displayName) vs \(red.displayName) · \(size)×\(size)"
    }
}

/// How quickly two computers play each other.
enum WatchSpeed: String, CaseIterable, Identifiable, Codable, Sendable {
    case slow
    case normal
    case fast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }

    var symbolName: String {
        switch self {
        case .slow: return "tortoise"
        case .normal: return "figure.walk"
        case .fast: return "hare"
        }
    }

    var delay: Duration {
        switch self {
        case .slow: return .milliseconds(900)
        case .normal: return .milliseconds(350)
        case .fast: return .zero
        }
    }
}
