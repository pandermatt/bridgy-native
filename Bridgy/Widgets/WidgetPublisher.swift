#if os(iOS)
import BridgyEngine
import BridgyLive
import SwiftUI
import WidgetKit

/// Keeps the home-screen widget in step with the game: after every move and
/// when a game ends, the board and a line of status go to the shared App
/// Group and the widget is asked to reload.
@MainActor
enum WidgetPublisher {

    static func publish(_ session: GameSession, settings: AppSettings) {
        let state = session.state
        let configuration = session.configuration
        let title: String
        if let winner = state.winner {
            title = configuration.soloHumanPlayer == winner ? "You won"
                : configuration.soloHumanPlayer != nil ? "\(configuration.seat(for: winner).displayName) won"
                : "\(winner.displayName) won"
        } else if session.isHumanTurn, configuration.soloHumanPlayer != nil {
            title = "Your move"
        } else {
            title = "\(session.currentSeat.displayName) to move"
        }
        let snapshot = WidgetSnapshot(
            title: title,
            detail: configuration.summary,
            moves: state.moveCount,
            isYourTurn: session.isHumanTurn,
            isOver: state.isOver
        )
        snapshot.save()
        writeBoard(state, settings: settings)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// No game to continue: the widget offers a new one or a puzzle.
    static func clear() {
        WidgetSnapshot.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func writeBoard(_ state: GameState, settings: AppSettings) {
        guard let url = WidgetSnapshot.boardURL else { return }
        let renderer = ImageRenderer(content:
            BoardCanvas(
                state: state,
                theme: settings.theme,
                style: settings.boardStyle,
                cap: settings.bridgeCap,
                highlightsLastMove: false
            )
            .frame(width: 300, height: 300)
        )
        renderer.scale = 2
        try? renderer.uiImage?.pngData()?.write(to: url, options: .atomic)
    }
}
#endif
