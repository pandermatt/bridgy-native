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
                candidate: candidate(in: geometry),
                hint: session.hintMove
            )
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

    /// Ghosts the cell the pointer is over, so a click is never a guess.
    private func candidate(in geometry: BoardGeometry) -> Move? {
        guard session.isHumanTurn, let hoverPoint else { return nil }
        return geometry.nearestCell(to: hoverPoint) { session.state.isLegal($0) }
    }

    private var accessibilityValue: String {
        var parts = [session.statusText]
        let readout = session.readout
        if let blue = readout.blue { parts.append("Blue needs \(blue) more") }
        if let red = readout.red { parts.append("Red needs \(red) more") }
        return parts.joined(separator: ". ")
    }
}
