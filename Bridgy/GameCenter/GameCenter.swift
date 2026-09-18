import BridgyEngine
import Foundation
import GameKit
import os

private let gcLog = Logger(subsystem: "ch.pandermatt.bridgy", category: "GameCenter")

/// Achievements and leaderboards. Quiet if the player isn't signed in, or
/// hasn't set Game Center up for Bridgy yet — a game should never nag.
///
/// The IDs below must exist in App Store Connect; until they do, reports
/// fail and are only logged.
@MainActor
enum GameCenter {

    enum Achievement: String, CaseIterable {
        case firstWin = "bridgy.first_win"
        case beatHard = "bridgy.beat_hard"
        case beatExpert = "bridgy.beat_expert"
        /// Beat Perfect while playing second — possible only because Perfect
        /// has no winning strategy there.
        case beatPerfectAcross = "bridgy.beat_perfect_across"
        case bigBoard = "bridgy.big_board"
        case agentBeatsYou = "bridgy.agent_beats_you"
        case trainedAgent = "bridgy.trained_agent"
        case tenPuzzles = "bridgy.puzzle_10"
    }

    enum Leaderboard: String {
        case puzzlesSolved = "bridgy.puzzles_solved"
        case fastestWin6x6 = "bridgy.fastest_win_6x6"
    }

    static var isSignedIn: Bool { GKLocalPlayer.local.isAuthenticated }

    /// At launch. If the system wants to show its sign-in, it's shown once.
    static func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            MainActor.assumeIsolated {
                if let error { gcLog.notice("Game Center: \(error.localizedDescription, privacy: .public)") }
                #if canImport(UIKit)
                if let viewController { present(viewController) }
                #endif
            }
        }
    }

    #if canImport(UIKit)
    private static func present(_ controller: UIViewController) {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        top?.present(controller, animated: true)
    }
    #endif

    // MARK: - Reporting

    /// A game you finished in Play.
    static func gameFinished(_ game: PlayedGame) {
        guard isSignedIn, let me = game.configuration.soloHumanPlayer else { return }
        let opponent = game.configuration.seat(for: me.opponent)
        var earned: [Achievement] = []
        if game.record.winner == me {
            earned.append(.firstWin)
            if game.record.size >= 10 { earned.append(.bigBoard) }
            switch opponent.difficulty {
            case .hard?: earned.append(.beatHard)
            case .expert?: earned += [.beatHard, .beatExpert]
            case .perfect?:
                earned += [.beatHard, .beatExpert]
                if me == .red { earned.append(.beatPerfectAcross) }
            default: break
            }
            let strong = opponent.difficulty.map { [.hard, .expert, .perfect].contains($0) } ?? opponent.isAgent
            if game.record.size == 6, strong {
                submit(game.record.length, to: .fastestWin6x6)
            }
        } else if opponent.isAgent {
            earned.append(.agentBeatsYou)
        }
        complete(earned)
    }

    static func puzzlesChanged(solved: Int) {
        guard isSignedIn else { return }
        submit(solved, to: .puzzlesSolved)
        report(.tenPuzzles, percent: min(100, Double(solved) * 10))
    }

    static func agentTrained() {
        guard isSignedIn else { return }
        complete([.trainedAgent])
    }

    private static func complete(_ achievements: [Achievement]) {
        for achievement in Set(achievements.map(\.rawValue)) {
            report(Achievement(rawValue: achievement)!, percent: 100)
        }
    }

    private static func report(_ achievement: Achievement, percent: Double) {
        let item = GKAchievement(identifier: achievement.rawValue)
        item.percentComplete = percent
        item.showsCompletionBanner = percent >= 100
        Task {
            do { try await GKAchievement.report([item]) } catch {
                gcLog.notice("Achievement \(achievement.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func submit(_ score: Int, to leaderboard: Leaderboard) {
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [leaderboard.rawValue]
                )
            } catch {
                gcLog.notice("Leaderboard \(leaderboard.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension Seat {
    var isAgent: Bool {
        if case .agent = self { return true }
        return false
    }
}
