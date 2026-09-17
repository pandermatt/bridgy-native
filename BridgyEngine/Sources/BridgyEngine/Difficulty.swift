import Foundation

/// The opponent strengths offered in the UI.
///
/// The original exposed eleven algorithms crossed with strategies and modes in a
/// combo box, though its own placeholder text read "-- Schwierigkeit --". These
/// are those algorithms, presented as the ladder they were always meant to be.
public enum Difficulty: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case easy
    case casual
    case medium
    case hard
    case expert
    case perfect

    public var id: String { rawValue }

    /// Above this size Monte Carlo search is spread too thin to help, and plain
    /// pathfinding plays better.
    static let searchSizeLimit = 16

    public var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .casual: return "Casual"
        case .medium: return "Medium"
        case .hard: return "Hard"
        case .expert: return "Expert"
        case .perfect: return "Perfect"
        }
    }

    public var symbolName: String {
        switch self {
        case .easy: return "tortoise"
        case .casual: return "hare"
        case .medium: return "flame"
        case .hard: return "bolt"
        case .expert: return "cpu"
        case .perfect: return "crown"
        }
    }

    public var summary: String {
        switch self {
        case .easy:
            return "Plays at random. A good way to learn the shape of the board."
        case .casual:
            return "Builds its own chain and never looks at yours."
        case .medium:
            return "Weighs its chain against yours and picks whichever matters more."
        case .hard:
            return "Counts the moves you each need and plays on whichever route decides the game."
        case .expert:
            return "Plays out thousands of random finishes a turn and follows what wins."
        case .perfect:
            return "Plays the known solution to Bridg-It. Going first, it cannot be beaten."
        }
    }

    /// An honest caveat, where one is due.
    public var caveat: String? {
        switch self {
        case .perfect:
            return "The second player has no winning strategy, so playing second it falls back to Expert."
        default:
            return nil
        }
    }

    /// Builds the engine for this level, tuned to the board.
    /// `thinkingBudget` caps how long a searching engine may take. It exists so
    /// that watching two computers at speed can hold the requested rate: the only
    /// engine it affects is Monte Carlo, which then simply searches less. The
    /// others are effectively instant and ignore it.
    public func engine(forSize size: Int, thinkingBudget: Duration? = nil) -> any Engine {
        switch self {
        case .easy:
            return RandomEngine()
        case .casual:
            return GreedyEngine(strategy: .aggressive)
        case .medium:
            return GreedyEngine(strategy: .balanced)
        case .hard:
            return ShortestPathEngine(strategy: .balanced, tieBreak: .avoidConnection)
        case .expert:
            return Self.expertEngine(forSize: size, thinkingBudget: thinkingBudget)
        case .perfect:
            return PerfectEngine(
                fallback: Self.expertEngine(forSize: size, thinkingBudget: thinkingBudget)
            )
        }
    }

    /// The same ladder, but with every engine's cost bounded.
    ///
    /// A tournament plays hundreds of games back to back, so Expert switches
    /// from a wall-clock budget to a fixed number of playouts. That also makes
    /// the whole run reproducible from its seed.
    public func tournamentEngine(forSize size: Int) -> any Engine {
        switch self {
        case .expert:
            return size <= Self.searchSizeLimit
                ? MCTSEngine(iterations: 400)
                : ShortestPathEngine(strategy: .balanced, tieBreak: .disturbOpponent)
        case .perfect:
            return PerfectEngine(fallback: Difficulty.expert.tournamentEngine(forSize: size))
        default:
            return engine(forSize: size)
        }
    }

    private static func expertEngine(forSize size: Int, thinkingBudget: Duration? = nil) -> any Engine {
        guard size <= searchSizeLimit else {
            return ShortestPathEngine(strategy: .balanced, tieBreak: .disturbOpponent)
        }
        // Bigger boards need longer to search, but not without limit.
        let milliseconds = min(2_000, 400 + size * size * 12)
        var budget = Duration.milliseconds(milliseconds)
        if let thinkingBudget, thinkingBudget < budget { budget = thinkingBudget }
        return MCTSEngine(timeBudget: budget)
    }
}
