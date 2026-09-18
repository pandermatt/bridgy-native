import Foundation

/// Significance tests for win counts.
public enum Significance {

    /// Two-sided exact binomial p-value for `wins` out of `games` under a true
    /// rate of `p`: the probability of any outcome no more likely than this one.
    public static func binomialPValue(wins: Int, games: Int, p: Double = 0.5) -> Double {
        guard games > 0 else { return 1 }
        let observed = logBinomial(wins, games, p)
        var total = 0.0
        for k in 0...games {
            let l = logBinomial(k, games, p)
            // A little slack so outcomes equally likely by symmetry count.
            if l <= observed + 1e-7 { total += exp(l) }
        }
        return min(1, total)
    }

    static func logBinomial(_ k: Int, _ n: Int, _ p: Double) -> Double {
        let choose = lgamma(Double(n + 1)) - lgamma(Double(k + 1)) - lgamma(Double(n - k + 1))
        let hits = k == 0 ? 0 : Double(k) * log(p)
        let misses = k == n ? 0 : Double(n - k) * log(1 - p)
        return choose + hits + misses
    }

    /// Holm–Bonferroni adjusted p-values, in the order given. Testing every
    /// pairing of a tournament is many tests at once; unadjusted, one in twenty
    /// "significant" differences would be noise.
    public static func holm(_ pValues: [Double]) -> [Double] {
        let m = pValues.count
        let order = pValues.indices.sorted { pValues[$0] < pValues[$1] }
        var adjusted = [Double](repeating: 1, count: m)
        var running = 0.0
        for (rank, index) in order.enumerated() {
            running = max(running, min(1, Double(m - rank) * pValues[index]))
            adjusted[index] = running
        }
        return adjusted
    }

    /// Games needed for a 95% interval about ±`halfWidth` wide around a rate
    /// near `rate`. A planning figure, not a guarantee.
    public static func gamesNeeded(halfWidth: Double, rate: Double = 0.5, z: Double = 1.96) -> Int {
        guard halfWidth > 0 else { return .max }
        return Int((z * z * rate * (1 - rate) / (halfWidth * halfWidth)).rounded(.up))
    }
}

/// Wald's sequential probability ratio test on a win rate.
///
/// Instead of fixing the number of games in advance, play until the evidence
/// settles the question: is the rate at most `p0` (H0) or at least `p1` (H1)?
/// Error rates are held at `alpha` (wrongly accepting H1) and `beta` (wrongly
/// accepting H0). This is how chess engines are tested, and it typically needs
/// far fewer games than a fixed-size test with the same guarantees.
public struct SequentialTest: Sendable, Hashable, Codable {
    public enum Decision: String, Sendable, Hashable, Codable {
        case undecided, acceptH0, acceptH1
    }

    public let p0: Double
    public let p1: Double
    public let alpha: Double
    public let beta: Double
    public private(set) var wins = 0
    public private(set) var games = 0
    public private(set) var logLikelihoodRatio = 0.0

    public init(p0: Double, p1: Double, alpha: Double = 0.05, beta: Double = 0.05) {
        precondition(p0 < p1 && p0 > 0 && p1 < 1, "Need 0 < p0 < p1 < 1")
        self.p0 = p0
        self.p1 = p1
        self.alpha = alpha
        self.beta = beta
    }

    /// Crossing this accepts H1.
    public var upperBound: Double { log((1 - beta) / alpha) }
    /// Crossing this accepts H0.
    public var lowerBound: Double { log(beta / (1 - alpha)) }

    public var decision: Decision {
        if logLikelihoodRatio >= upperBound { return .acceptH1 }
        if logLikelihoodRatio <= lowerBound { return .acceptH0 }
        return .undecided
    }

    public mutating func record(win: Bool) {
        games += 1
        if win {
            wins += 1
            logLikelihoodRatio += log(p1 / p0)
        } else {
            logLikelihoodRatio += log((1 - p1) / (1 - p0))
        }
    }
}
