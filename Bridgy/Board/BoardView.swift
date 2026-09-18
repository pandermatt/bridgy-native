import BridgyEngine
import SwiftUI

/// The interactive board: drawing comes from `BoardCanvas`, this adds input.
///
/// Input is a tap and nothing else. The drag-between-dots gesture is gone — on a
/// touchscreen, tapping the gap you want is the natural move, and maintaining a
/// second way in was buying nothing.
struct BoardView: View {

    @Bindable var session: GameSession
    var settings: AppSettings

    @State private var hoverPoint: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let geometry = BoardGeometry(
                board: session.board,
                rect: CGRect(origin: .zero, size: proxy.size)
            )
            BoardCanvas(
                state: session.state,
                theme: settings.theme,
                style: settings.boardStyle,
                cap: settings.bridgeCap,
                guideDots: !session.configuration.isWatchOnly,
                // Gold for your win (or any win you're watching); a loss shows
                // the winner's chain as it is.
                winningPath: celebrates ? nil : (settings.highlightsWinningPath ? session.winningPath : nil),
                candidate: candidate(in: geometry),
                hint: session.hintMove,
                highlightsLastMove: !session.state.isOver
            )
            .overlay {
                // Keyed on the final move, so a new win celebrates afresh.
                if celebrates, settings.highlightsWinningPath {
                    WinningPathCelebration(state: session.state, style: settings.boardStyle, cap: settings.bridgeCap)
                        .id(session.state.moveCount)
                }
            }
            .contentShape(.rect)
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard session.isHumanTurn else { return }
                        let move = geometry.nearestCell(to: value.location) {
                            session.state.isLegal($0)
                        }
                        if let move { session.play(move) }
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hoverPoint = point
                case .ended: hoverPoint = nil
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Game board, \(session.board.size) by \(session.board.size)")
            // Built from the session's cached readout. This used to call
            // `movesToWin` for both players, and because the argument is a plain
            // String it ran on every single body pass whether or not VoiceOver
            // was listening — two graph builds and two searches, per render.
            .accessibilityValue(accessibilityValue)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var celebrates: Bool {
        guard let winner = session.state.winner else { return false }
        guard let me = session.configuration.soloHumanPlayer else { return true }
        return me == winner
    }

    /// Ghosts the cell the pointer is over, so a click is never a guess.
    private func candidate(in geometry: BoardGeometry) -> Move? {
        guard session.isHumanTurn, let hoverPoint else { return nil }
        return geometry.nearestCell(to: hoverPoint) { session.state.isLegal($0) }
    }

    private var accessibilityValue: String {
        var parts = [session.statusText]
        let readout = session.readout
        if let down = readout.blue { parts.append("\(Player.blue.displayName) needs \(down) more") }
        if let across = readout.red { parts.append("\(Player.red.displayName) needs \(across) more") }
        return parts.joined(separator: ". ")
    }
}
