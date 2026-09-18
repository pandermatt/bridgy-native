import Foundation

/// Strengths fitted to a whole set of games at once, with the advantage of
/// moving first as a separate term.
///
/// The model is Bradley–Terry with a "home" effect: the chance that `i`,
/// playing Down, beats `j` is `σ(βᵢ − βⱼ + γ)`. Fitting all games together
/// answers what Elo's running tally cannot: how strong each engine is once
/// colour is accounted for, and how much moving first is worth once strength
/// is accounted for. A tournament's raw first-player rate mixes the two — if a
/// strong engine happens to play Across more against weak ones, the raw rate
/// says Across is favoured when it is only the stronger player.
///
/// A ridge penalty keeps the fit finite when an engine never loses (as Perfect
/// never does as Down), where the unpenalised estimate runs to infinity.
///
/// One caution, learned from real tournaments: the model assumes moving first
/// is worth the same to everyone, and in Bridg-It it is not. Perfect as Down
/// wins every game; two evenly matched heuristics gain only a few points. Fed
/// both, the single first-move term is pulled far above what any ordinary
/// pairing sees. With a balanced schedule — every pairing in both colours
/// equally, as tournaments here always are — the raw first-player rate is
/// already unconfounded and is the better headline; mirror matches give it per
/// engine. Use this for strengths.
public struct BradleyTerry: Sendable, Hashable {

    public struct Game: Sendable, Hashable {
        public let down: Int
        public let across: Int
        public let downWon: Bool

        public init(down: Int, across: Int, downWon: Bool) {
            self.down = down
            self.across = across
            self.downWon = downWon
        }
    }

    /// Log-strength per participant, centred on zero.
    public let strengths: [Double]
    /// Log-odds added to Down's side: the value of moving first.
    public let firstMove: Double

    /// Strengths on the Elo scale, centred on 1500, so they read like ratings.
    public var ratings: [Double] { strengths.map { 1500 + $0 * 400 / log(10) } }

    /// How often Down wins between two equally strong players.
    public var firstMoveWinRate: Double { Self.sigmoid(firstMove) }

    public func probability(down: Int, beats across: Int) -> Double {
        Self.sigmoid(strengths[down] - strengths[across] + firstMove)
    }

    static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    /// Maximum penalised likelihood by Newton's method. A handful of iterations
    /// is plenty: the problem is small and the penalised likelihood concave.
    public static func fit(_ games: [Game], participants: Int, ridge: Double = 0.1) -> BradleyTerry {
        let n = participants
        let k = n + 1
        var x = [Double](repeating: 0, count: k)
        for _ in 0..<50 {
            var gradient = x.map { -ridge * $0 }
            var hessian = [Double](repeating: 0, count: k * k)
            for i in 0..<k { hessian[i * k + i] = ridge }
            for game in games where game.down != game.across {
                let eta = x[game.down] - x[game.across] + x[n]
                let p = sigmoid(eta)
                let residual = (game.downWon ? 1 : 0) - p
                let weight = p * (1 - p)
                let indices = [game.down, game.across, n]
                let signs: [Double] = [1, -1, 1]
                for a in 0..<3 {
                    gradient[indices[a]] += signs[a] * residual
                    for b in 0..<3 {
                        hessian[indices[a] * k + indices[b]] += signs[a] * signs[b] * weight
                    }
                }
            }
            guard let step = solve(hessian, gradient, size: k) else { break }
            for i in 0..<k { x[i] += step[i] }
            if step.map(abs).max() ?? 0 < 1e-9 { break }
        }
        let strengths = Array(x[0..<n])
        let mean = strengths.isEmpty ? 0 : strengths.reduce(0, +) / Double(n)
        return BradleyTerry(strengths: strengths.map { $0 - mean }, firstMove: x[n])
    }

    /// Solves `A x = b` by Gaussian elimination with partial pivoting.
    static func solve(_ matrix: [Double], _ vector: [Double], size k: Int) -> [Double]? {
        var a = matrix
        var b = vector
        for column in 0..<k {
            guard let pivot = (column..<k).max(by: { abs(a[$0 * k + column]) < abs(a[$1 * k + column]) }),
                  abs(a[pivot * k + column]) > 1e-12 else { return nil }
            if pivot != column {
                for j in 0..<k { a.swapAt(pivot * k + j, column * k + j) }
                b.swapAt(pivot, column)
            }
            for row in (column + 1)..<k {
                let factor = a[row * k + column] / a[column * k + column]
                guard factor != 0 else { continue }
                for j in column..<k { a[row * k + j] -= factor * a[column * k + j] }
                b[row] -= factor * b[column]
            }
        }
        var x = [Double](repeating: 0, count: k)
        for row in stride(from: k - 1, through: 0, by: -1) {
            var sum = b[row]
            for j in (row + 1)..<k { sum -= a[row * k + j] * x[j] }
            x[row] = sum / a[row * k + row]
        }
        return x
    }
}

/// Bradley–Terry estimates with bootstrap intervals.
public struct RatingAnalysis: Sendable, Hashable {
    public let fit: BradleyTerry
    /// 95% percentile intervals, on the Elo scale.
    public let ratingIntervals: [ConfidenceInterval]
    /// 95% percentile interval for how often Down wins between equals.
    public let firstMoveInterval: ConfidenceInterval

    /// Refits on `resamples` resamplings of the games, drawn with replacement.
    /// Seeded, so the same games always give the same intervals.
    public static func run(
        _ games: [BradleyTerry.Game],
        participants: Int,
        resamples: Int = 200,
        seed: UInt64 = 0xB007
    ) -> RatingAnalysis {
        let fit = BradleyTerry.fit(games, participants: participants)
        guard !games.isEmpty, resamples > 1 else {
            let wide = ConfidenceInterval(low: 0, high: 1)
            return RatingAnalysis(fit: fit, ratingIntervals: fit.ratings.map { ConfidenceInterval(low: $0, high: $0) },
                                  firstMoveInterval: wide)
        }
        var rng = SeededRandomNumberGenerator(seed: seed)
        var ratings = [[Double]](repeating: [], count: participants)
        var first: [Double] = []
        for _ in 0..<resamples {
            let sample = (0..<games.count).map { _ in games[Int.random(in: 0..<games.count, using: &rng)] }
            let refit = BradleyTerry.fit(sample, participants: participants)
            for (index, rating) in refit.ratings.enumerated() { ratings[index].append(rating) }
            first.append(refit.firstMoveWinRate)
        }
        return RatingAnalysis(
            fit: fit,
            ratingIntervals: ratings.map(Self.percentileInterval),
            firstMoveInterval: Self.percentileInterval(first)
        )
    }

    static func percentileInterval(_ values: [Double]) -> ConfidenceInterval {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return ConfidenceInterval(low: 0, high: 0) }
        func at(_ q: Double) -> Double { sorted[min(sorted.count - 1, max(0, Int((q * Double(sorted.count - 1)).rounded())))] }
        return ConfidenceInterval(low: at(0.025), high: at(0.975))
    }
}
