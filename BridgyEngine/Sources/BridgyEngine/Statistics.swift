import Foundation

/// A range a true proportion plausibly lies in.
public struct ConfidenceInterval: Sendable, Hashable {
    public let low: Double
    public let high: Double

    public init(low: Double, high: Double) {
        self.low = low
        self.high = high
    }

    public var width: Double { high - low }

    /// Formatted as a percentage range, for tables.
    public func description(fractionDigits: Int = 0) -> String {
        String(format: "%.\(fractionDigits)f–%.\(fractionDigits)f%%", low * 100, high * 100)
    }
}

public enum Statistics {

    /// Wilson score interval for a win rate.
    ///
    /// The obvious interval — the normal approximation — is badly wrong exactly
    /// where a tournament spends most of its time: small samples and rates near
    /// 0 or 1. Two games out of two gives "100% ± 0", which says nothing. The
    /// Wilson interval stays inside [0, 1] and stays honest about small `total`,
    /// which is the whole reason for showing an interval at all.
    public static func wilsonInterval(wins: Int, total: Int, z: Double = 1.96) -> ConfidenceInterval {
        guard total > 0 else { return ConfidenceInterval(low: 0, high: 1) }
        let n = Double(total)
        let p = Double(wins) / n
        let zSquared = z * z
        let denominator = 1 + zSquared / n
        let centre = (p + zSquared / (2 * n)) / denominator
        let margin = (z / denominator) * (p * (1 - p) / n + zSquared / (4 * n * n)).squareRoot()
        return ConfidenceInterval(
            low: max(0, centre - margin),
            high: min(1, centre + margin)
        )
    }
}

/// Elo ratings, updated one game at a time.
///
/// Sequential rather than fitted at the end, so the ratings can be plotted as
/// they converge — which is far more informative than a final table, because
/// you can see when the field has actually separated.
public struct EloRating: Sendable, Hashable {
    public static let initialRating = 1500.0

    public let kFactor: Double
    public private(set) var ratings: [Double]

    public init(count: Int, kFactor: Double = 24) {
        self.kFactor = kFactor
        self.ratings = [Double](repeating: Self.initialRating, count: count)
    }

    public subscript(index: Int) -> Double { ratings[index] }

    /// Probability that `player` beats `opponent`, given current ratings.
    public func expectedScore(_ player: Int, against opponent: Int) -> Double {
        1 / (1 + pow(10, (ratings[opponent] - ratings[player]) / 400))
    }

    public mutating func record(winner: Int, loser: Int) {
        guard winner != loser,
              ratings.indices.contains(winner),
              ratings.indices.contains(loser) else { return }
        let expected = expectedScore(winner, against: loser)
        let adjustment = kFactor * (1 - expected)
        ratings[winner] += adjustment
        ratings[loser] -= adjustment
    }
}
