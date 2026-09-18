import BridgyEngine
import SwiftUI

/// The one place the board is drawn.
///
/// Used by the interactive board, the rules demo, and the shared image, so a
/// style cannot end up meaning three different things.
struct BoardCanvas: View {
    let state: GameState
    let theme: BoardTheme
    let style: BoardStyle
    var cap: BridgeCap = .rounded
    /// Faint markers on the dots the style would not otherwise draw, so a human
    /// has something to aim at. Off while two computers play.
    var guideDots = false
    /// Fades the loser's bridges once the game is decided.
    var dimsLoser = true
    /// Cells of the chain that won, passed in already computed so the canvas
    /// never searches during a redraw.
    var winningPath: Set<Int>?
    /// Ghosted cell under the pointer, on devices that have one.
    var candidate: Move?
    /// Suggested move, ringed rather than played.
    var hint: Move?
    /// The halo on the move just played — off for a finished board being shared.
    var highlightsLastMove = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let geometry = BoardGeometry(
                board: state.board,
                rect: CGRect(origin: .zero, size: proxy.size)
            )
            Canvas { context, _ in
                draw(in: &context, geometry: geometry)
            }
        }
    }

    /// Straight off the lattice, so "Bolder touches its neighbours" stays true
    /// at every board size. The old path multiplied `lineWidth`, which carried a
    /// 2pt floor and stopped tracking the lattice on large boards.
    private func width(_ geometry: BoardGeometry) -> CGFloat {
        max(1, geometry.scale * style.strokeLatticeWidth)
    }

    private func draw(in context: inout GraphicsContext, geometry: BoardGeometry) {
        drawDots(in: &context, geometry: geometry)
        drawPlacedEdges(in: &context, geometry: geometry)
        drawWinningPath(in: &context, geometry: geometry)
        drawCandidate(in: &context, geometry: geometry)
        drawHint(in: &context, geometry: geometry)
    }

    // MARK: - Dots

    private func drawDots(in context: inout GraphicsContext, geometry: BoardGeometry) {
        guard style.dots != .none || guideDots else { return }
        let radius = geometry.dotRadius

        for player in Player.allCases {
            let touched = style.dots == .connectedOnly ? connectedDots(for: player) : nil
            var path = Path()
            var guides = Path()
            for dot in geometry.dots(for: player) {
                var drawn = style.dots != .none
                if let touched {
                    let stride = player == .blue ? state.board.size : state.board.size + 1
                    drawn = touched.contains(dot.row * stride + dot.col)
                }
                let centre = geometry.point(of: dot)
                if drawn {
                    path.addEllipse(in: CGRect(
                        x: centre.x - radius, y: centre.y - radius,
                        width: radius * 2, height: radius * 2
                    ))
                } else if guideDots {
                    // The dot this style would have hidden. A human still has to
                    // aim at it, so it gets a smaller, fainter marker rather than
                    // an empty board.
                    let guide = max(1, radius * 0.55)
                    guides.addEllipse(in: CGRect(
                        x: centre.x - guide, y: centre.y - guide,
                        width: guide * 2, height: guide * 2
                    ))
                }
            }
            let colour = theme.color(for: player)
            // Faint dots recede on white but vanish on black, so dark mode
            // draws them brighter.
            let dark = colorScheme == .dark
            context.fill(path, with: .color(style.dots == .connectedOnly ? colour : colour.opacity(dark ? 0.72 : 0.45)))
            context.fill(guides, with: .color(colour.opacity(dark ? 0.45 : 0.28)))
        }
    }

    /// The chain that won, drawn over the main pass so it reads on every style.
    private func drawWinningPath(in context: inout GraphicsContext, geometry: BoardGeometry) {
        guard let winningPath, !winningPath.isEmpty, let winner = state.winner else { return }
        let stroke = width(geometry)

        var path = Path()
        for cell in winningPath.sorted() {
            let (from, to) = geometry.endpoints(of: state.board.move(at: cell), for: winner)
            path.move(to: from)
            path.addLine(to: to)
        }

        let colour = theme.color(for: winner)
        // A soft spread first, then the chain at full strength. At Bolder there
        // is no room beside a bridge, so the spread is kept under one lattice
        // unit and the chain is marked from the inside instead.
        if style.fillsItsCell {
            context.stroke(
                path,
                with: .color(colour),
                style: StrokeStyle(lineWidth: stroke, lineCap: cap.lineCap, lineJoin: cap.lineJoin)
            )
            context.stroke(
                path,
                with: .color(.white.opacity(0.5)),
                style: StrokeStyle(lineWidth: stroke * 0.22, lineCap: cap.lineCap)
            )
        } else {
            context.stroke(
                path,
                with: .color(colour.opacity(0.3)),
                style: StrokeStyle(lineWidth: stroke * 2.4, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                path,
                with: .color(colour),
                style: StrokeStyle(lineWidth: stroke * 1.15, lineCap: cap.lineCap, lineJoin: cap.lineJoin)
            )
        }
    }

    /// Dot ids this player has actually built onto.
    private func connectedDots(for player: Player) -> Set<Int> {
        var touched = Set<Int>()
        for cell in 0..<state.board.cellCount where state.cells[cell] == player {
            let (a, b) = state.board.endpoints(state.board.move(at: cell), for: player)
            touched.insert(a)
            touched.insert(b)
        }
        return touched
    }

    // MARK: - Edges

    private func drawPlacedEdges(in context: inout GraphicsContext, geometry: BoardGeometry) {
        let stroke = width(geometry)
        let lastMove = highlightsLastMove ? state.moves.last : nil
        // A halo needs room beside the bridge. Bolder has none, so there the last
        // move stays in the main pass and is marked from the inside instead.
        let haloed = style.fillsItsCell ? nil : lastMove

        for player in Player.allCases {
            var path = Path()
            for cell in 0..<state.board.cellCount where state.cells[cell] == player {
                let move = state.board.move(at: cell)
                if move == haloed { continue }
                let (from, to) = geometry.endpoints(of: move, for: player)
                path.move(to: from)
                path.addLine(to: to)
            }
            let isWinner = state.winner == player
            let colour = theme.color(for: player)
            let opacity = !dimsLoser || state.winner == nil || isWinner ? 1 : 0.35

            if style.glows {
                context.stroke(
                    path,
                    with: .color(colour.opacity(0.35 * opacity)),
                    style: StrokeStyle(lineWidth: stroke * 2.6, lineCap: cap.lineCap, lineJoin: cap.lineJoin)
                )
            }
            context.stroke(
                path,
                with: .color(colour.opacity(opacity)),
                style: StrokeStyle(lineWidth: stroke, lineCap: cap.lineCap, lineJoin: cap.lineJoin)
            )
        }

        // The move just played is marked, so it is obvious what changed — the
        // original drew it dashed for the same reason.
        guard let lastMove, let owner = state.owner(of: lastMove) else { return }
        let (from, to) = geometry.endpoints(of: lastMove, for: owner)
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        let colour = theme.color(for: owner)
        // Match the dimming the rest of this player's bridges get once the game
        // is decided; the halo used to ignore it and sit at full colour.
        let opacity = !dimsLoser || state.winner == nil || state.winner == owner ? 1.0 : 0.35

        if style.fillsItsCell {
            // Contained entirely within the bridge, so it cannot bleed into a
            // neighbour that is touching it.
            context.stroke(
                path,
                with: .color(.white.opacity(0.45 * opacity)),
                style: StrokeStyle(lineWidth: stroke * 0.28, lineCap: cap.lineCap)
            )
        } else {
            context.stroke(
                path,
                with: .color(colour.opacity(0.35 * opacity)),
                style: StrokeStyle(lineWidth: stroke * 2.1, lineCap: cap.lineCap)
            )
            context.stroke(
                path,
                with: .color(colour.opacity(opacity)),
                style: StrokeStyle(lineWidth: stroke, lineCap: cap.lineCap)
            )
        }
    }

    private func drawCandidate(in context: inout GraphicsContext, geometry: BoardGeometry) {
        guard let candidate, state.isLegal(candidate) else { return }
        let (from, to) = geometry.endpoints(of: candidate, for: state.current)
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(
            path,
            with: .color(theme.color(for: state.current).opacity(0.4)),
            style: StrokeStyle(lineWidth: width(geometry), lineCap: cap.lineCap)
        )
    }

    private func drawHint(in context: inout GraphicsContext, geometry: BoardGeometry) {
        guard let hint, state.isLegal(hint) else { return }
        let centre = geometry.center(of: hint)
        let radius = max(geometry.scale * 0.55, 8)
        let ring = Path(ellipseIn: CGRect(
            x: centre.x - radius, y: centre.y - radius,
            width: radius * 2, height: radius * 2
        ))
        context.stroke(
            ring,
            with: .color(theme.color(for: state.current)),
            style: StrokeStyle(
                lineWidth: max(1.5, geometry.scale * 0.1),
                dash: [radius * 0.5, radius * 0.35]
            )
        )
    }
}
