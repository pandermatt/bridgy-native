import BridgyEngine
import SwiftUI

/// The playing surface.
///
/// Everything is drawn in a single `Canvas`, which keeps a 35×35 board — 2,381
/// cells and over 2,500 dots — to one pass instead of thousands of views.
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
            Canvas { context, _ in
                draw(in: &context, geometry: geometry)
            }
            .contentShape(.rect)
            .gesture(gesture(for: geometry))
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hoverPoint = point
                case .ended: hoverPoint = nil
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Game board, \(session.board.size) by \(session.board.size)")
            .accessibilityValue(accessibilityValue)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.smooth(duration: 0.18), value: session.state.moveCount)
    }

    private var accessibilityValue: String {
        var parts = [session.statusText]
        if let blue = session.movesToWin(for: .blue) { parts.append("Blue needs \(blue) more") }
        if let red = session.movesToWin(for: .red) { parts.append("Red needs \(red) more") }
        return parts.joined(separator: ". ")
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, geometry: BoardGeometry) {
        let state = session.state
        if settings.showDots { drawDots(in: &context, geometry: geometry) }
        drawPlacedEdges(in: &context, geometry: geometry, state: state)
        drawCandidate(in: &context, geometry: geometry, state: state)
        drawHint(in: &context, geometry: geometry, state: state)
        drawDrag(in: &context, geometry: geometry)
    }

    private func drawDots(in context: inout GraphicsContext, geometry: BoardGeometry) {
        let radius = geometry.dotRadius
        for player in Player.allCases {
            let color = settings.colorway.color(for: player)
            var path = Path()
            for dot in geometry.dots(for: player) {
                let centre = geometry.point(of: dot)
                path.addEllipse(in: CGRect(
                    x: centre.x - radius, y: centre.y - radius,
                    width: radius * 2, height: radius * 2
                ))
            }
            context.fill(path, with: .color(color.opacity(0.45)))
        }
    }

    private func drawPlacedEdges(in context: inout GraphicsContext, geometry: BoardGeometry, state: GameState) {
        let width = settings.boldLines ? geometry.boldLineWidth : geometry.lineWidth
        let lastMove = state.moves.last

        for player in Player.allCases {
            var path = Path()
            for cell in 0..<state.board.cellCount where state.cells[cell] == player {
                let move = state.board.move(at: cell)
                if move == lastMove { continue }   // drawn separately, brighter
                let (from, to) = geometry.endpoints(of: move, for: player)
                path.move(to: from)
                path.addLine(to: to)
            }
            let isWinner = state.winner == player
            let color = settings.colorway.color(for: player)
            context.stroke(
                path,
                with: .color(color.opacity(state.winner == nil || isWinner ? 1 : 0.35)),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )
        }

        // The move just played gets a halo, so it is obvious what changed —
        // the original drew it as a dashed line for the same reason.
        if let lastMove, let owner = state.owner(of: lastMove) {
            let (from, to) = geometry.endpoints(of: lastMove, for: owner)
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            let color = settings.colorway.color(for: owner)
            context.stroke(
                path,
                with: .color(color.opacity(0.35)),
                style: StrokeStyle(lineWidth: width * 2.1, lineCap: .round)
            )
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
        }
    }

    /// Ghosts the cell the pointer is over, so a click is never a guess.
    private func drawCandidate(in context: inout GraphicsContext, geometry: BoardGeometry, state: GameState) {
        guard session.isHumanTurn, session.dragOrigin == nil,
              let hoverPoint,
              let move = geometry.nearestCell(to: hoverPoint, isAllowed: { state.isLegal($0) })
        else { return }
        let (from, to) = geometry.endpoints(of: move, for: state.current)
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        let width = settings.boldLines ? geometry.boldLineWidth : geometry.lineWidth
        context.stroke(
            path,
            with: .color(settings.colorway.color(for: state.current).opacity(0.4)),
            style: StrokeStyle(lineWidth: width, lineCap: .round)
        )
    }

    /// Marks the suggested move with a ring, rather than playing it.
    private func drawHint(in context: inout GraphicsContext, geometry: BoardGeometry, state: GameState) {
        guard let hint = session.hintMove, state.isLegal(hint) else { return }
        let centre = geometry.center(of: hint)
        let radius = max(geometry.scale * 0.55, 8)
        let ring = Path(ellipseIn: CGRect(
            x: centre.x - radius, y: centre.y - radius,
            width: radius * 2, height: radius * 2
        ))
        context.stroke(
            ring,
            with: .color(settings.colorway.color(for: state.current)),
            style: StrokeStyle(lineWidth: max(1.5, geometry.scale * 0.1), dash: [radius * 0.5, radius * 0.35])
        )
    }

    /// Rubber band from the dot being dragged from, following the finger.
    private func drawDrag(in context: inout GraphicsContext, geometry: BoardGeometry) {
        guard let origin = session.dragOrigin, let point = session.dragPoint else { return }
        var path = Path()
        path.move(to: geometry.point(of: origin))
        path.addLine(to: point)
        context.stroke(
            path,
            with: .color(settings.colorway.color(for: session.state.current).opacity(0.7)),
            style: StrokeStyle(lineWidth: geometry.lineWidth, lineCap: .round, dash: [geometry.scale * 0.35, geometry.scale * 0.3])
        )
    }

    // MARK: - Input

    /// One gesture serves both ways of playing: drag from one dot to the next,
    /// or simply tap the gap where the bridge should go. The original Swing
    /// version supported click-then-click and drag; tapping the gap is the one
    /// that actually suits a touchscreen.
    private func gesture(for geometry: BoardGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard session.isHumanTurn else { return }
                if session.dragOrigin == nil {
                    session.dragOrigin = geometry.nearestDot(
                        to: value.startLocation,
                        for: session.state.current
                    )
                }
                session.dragPoint = value.location
            }
            .onEnded { value in
                defer {
                    session.dragOrigin = nil
                    session.dragPoint = nil
                }
                guard session.isHumanTurn else { return }
                let travelled = hypot(value.translation.width, value.translation.height)

                if travelled > geometry.scale * 0.5,
                   let origin = session.dragOrigin,
                   let landing = geometry.nearestDot(to: value.location, for: session.state.current),
                   let move = geometry.cell(between: origin, and: landing),
                   session.state.isLegal(move) {
                    session.play(move)
                    return
                }

                if let move = geometry.nearestCell(
                    to: value.location,
                    isAllowed: { session.state.isLegal($0) }
                ) {
                    session.play(move)
                }
            }
    }
}
