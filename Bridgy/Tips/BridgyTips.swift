import SwiftUI
import TipKit

/// Things worth knowing, shown once each, at the moment they become useful —
/// instead of a tour of everything before the first move.
enum BridgyTipEvents {
    /// A move you made in Play.
    static let movePlayed = Tips.Event(id: "movePlayed")
    /// A game you finished in Play.
    static let gameFinished = Tips.Event(id: "gameFinished")
    /// A game you won in Play.
    static let gameWon = Tips.Event(id: "gameWon")
}

struct HintTip: Tip {
    var title: Text { Text("Stuck?") }
    var message: Text? { Text("Tap the bulb in the toolbar to see a strong move on the board.") }
    var image: Image? { Image(systemName: "lightbulb") }
    var rules: [Rule] {
        #Rule(BridgyTipEvents.movePlayed) { $0.donations.count >= 2 }
    }
}

struct AnalyseTip: Tip {
    var title: Text { Text("See how it went") }
    var message: Text? { Text("Analyse replays the game with who was winning after each move, and can talk you through it.") }
    var image: Image? { Image(systemName: "chart.xyaxis.line") }
}

struct PuzzleTip: Tip {
    var title: Text { Text("Try a puzzle") }
    var message: Text? { Text("A position with a forced win in two or three moves. Can you find it?") }
    var image: Image? { Image(systemName: "puzzlepiece.extension") }
    var rules: [Rule] {
        #Rule(BridgyTipEvents.gameWon) { $0.donations.count >= 1 }
    }
}

struct AgentTip: Tip {
    var title: Text { Text("Train your own opponent") }
    var message: Text? { Text("Agents learn Bridg-It by playing themselves. Train one, then play it or enter it in the Lab.") }
    var image: Image? { Image(systemName: "brain.head.profile") }
    var rules: [Rule] {
        #Rule(BridgyTipEvents.gameFinished) { $0.donations.count >= 3 }
    }
}

#if os(visionOS)
struct TableTip: Tip {
    var title: Text { Text("Play it on a real table") }
    var message: Text? { Text("Put the board in your room and carry the bridges across by hand.") }
    var image: Image? { Image(systemName: "square.3.layers.3d") }
}
#endif

enum BridgyTips {
    private static let resetKey = "resetTipsOnLaunch"

    /// Call once at launch. Resetting has to happen before TipKit is
    /// configured, which is why "Show Tips Again" waits for the next launch.
    static func configure() {
        if UserDefaults.standard.bool(forKey: resetKey) {
            try? Tips.resetDatastore()
            UserDefaults.standard.set(false, forKey: resetKey)
        }
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    static func resetOnNextLaunch() {
        UserDefaults.standard.set(true, forKey: resetKey)
    }
}
