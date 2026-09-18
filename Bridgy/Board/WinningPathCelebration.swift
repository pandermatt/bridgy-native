import BridgyEngine
import SwiftUI

/// The winning chain, drawn in gold from one edge to the other when a game is won.
///
/// Sits over the board on the same geometry. The chain grows along the
/// winner's axis — top to bottom for Down, left to right for Across — so it
/// reads as the crossing it is. With Reduce Motion it simply appears.
struct WinningPathCelebration: View {
    let state: GameState
    let style: BoardStyle
    let cap: BridgeCap

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var glow = false

    static let gold = LinearGradient(
        colors: [Color(red: 1.0, green: 0.86, blue: 0.40), Color(red: 0.88, green: 0.63, blue: 0.0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        GeometryReader { proxy in
            let geometry = BoardGeometry(board: state.board, rect: CGRect(origin: .zero, size: proxy.size))
            let segments = orderedSegments(geometry)
            let shown = Int((Double(segments.count) * progress).rounded(.up))
            // As wide as a bridge in this style and a little more, so the gold
            // covers the chain rather than sitting inside it.
            let width = max(3, geometry.scale * style.strokeLatticeWidth * 1.15)
            let path = Path { path in
                for (from, to) in segments.prefix(shown) {
                    path.move(to: from)
                    path.addLine(to: to)
                }
            }
            path
                .stroke(Self.gold, style: StrokeStyle(lineWidth: width, lineCap: cap.lineCap, lineJoin: cap.lineJoin))
                .shadow(color: Color(red: 1, green: 0.78, blue: 0.2).opacity(glow ? 0.9 : 0.5), radius: glow ? width * 1.6 : width)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { progress = 1; glow = true; return }
            withAnimation(.easeInOut(duration: 1.2)) { progress = 1 }
            withAnimation(.easeInOut(duration: 1.0).delay(1.2).repeatCount(3, autoreverses: true)) { glow = true }
        }
    }

    /// The chain's bridges, ordered along the winner's axis.
    private func orderedSegments(_ geometry: BoardGeometry) -> [(CGPoint, CGPoint)] {
        guard let winner = state.winner else { return [] }
        let cells = WinningPath.forWinner(of: state)
        let along: (Move) -> Int = { move in
            let centre = state.board.center(of: move)
            return winner == .blue ? centre.y : centre.x
        }
        return cells.map { state.board.move(at: $0) }
            .sorted { along($0) < along($1) }
            .map { geometry.endpoints(of: $0, for: winner) }
    }
}
