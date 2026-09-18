import BridgyEngine
import CoreGraphics
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
///
/// There is no separate "watch" mode: putting a computer in both seats *is* one.
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

/// How fast two computers play each other, and whether they may take their time.
struct WatchPace: Hashable, Codable, Sendable {
    /// Target moves per second.
    var movesPerSecond: Double
    /// When true the slider only sets a *minimum* gap, and a slow engine takes
    /// as long as it needs. When false its search budget is capped to the gap,
    /// so the rate is always met and Monte Carlo simply searches less.
    var allowsFullThinking: Bool

    static let `default` = WatchPace(movesPerSecond: 2, allowsFullThinking: false)
    static let range: ClosedRange<Double> = 0.5...15

    /// Stands for "no pause at all". A plain number rather than infinity, which
    /// neither JSON nor the settings store will take.
    static let instantRate: Double = 1_000

    /// No artificial pause between moves: as fast as the engines can play.
    var isInstant: Bool { movesPerSecond >= Self.instantRate }

    /// Time allotted per move.
    var interval: Duration {
        isInstant ? .zero : .milliseconds(Int((1_000 / max(movesPerSecond, 0.01)).rounded()))
    }

    /// Budget handed to a searching engine, or `nil` to let it think fully.
    ///
    /// Floored, so that Instant removes the pause without also removing the
    /// thinking — a zero budget would turn Expert into a random player.
    var thinkingBudget: Duration? {
        allowsFullThinking ? nil : max(interval, .milliseconds(20))
    }

    var rateDescription: String {
        if isInstant { return "Instant" }
        return movesPerSecond < 1
            ? String(format: "%.1f moves per second", movesPerSecond)
            : String(format: "%.0f moves per second", movesPerSecond)
    }

    /// The slider works in log space so the slow end stays adjustable — the
    /// difference between 0.5/s and 1/s matters as much as 10/s and 15/s. One
    /// extra step past the fastest rate is Instant.
    var sliderPosition: Double {
        get { isInstant ? Self.sliderRange.upperBound : log2(movesPerSecond) }
        set {
            if newValue > log2(Self.range.upperBound) + 0.5 {
                movesPerSecond = Self.instantRate
            } else {
                movesPerSecond = min(Self.range.upperBound, max(Self.range.lowerBound, pow(2, newValue)))
            }
        }
    }

    static var sliderRange: ClosedRange<Double> {
        log2(range.lowerBound)...(log2(range.upperBound) + 1)
    }
}

/// How big a board stays comfortable to tap on a given screen.
enum BoardSizeLimit {
    /// Adjacent cell centres sit `√2` spacings apart, so this keeps distinct
    /// targets about 20pt from each other — enough to aim at with a finger.
    static let minimumSpacing: CGFloat = 14

    /// A board of size `n` spans `2n + 1.6` lattice units.
    static func maximumComfortableSize(forSide side: CGFloat) -> Int {
        guard side > 0 else { return Board.maximumSize }
        let raw = (side / minimumSpacing - 1.6) / 2
        return min(Board.maximumSize, max(Board.minimumSize, Int(raw.rounded(.down))))
    }

    /// The cap that actually applies: nobody has to tap when both seats are
    /// computers, so the whole range opens up.
    static func maximumSize(for configuration: GameConfiguration, side: CGFloat) -> Int {
        configuration.isWatchOnly ? Board.maximumSize : maximumComfortableSize(forSide: side)
    }
}
