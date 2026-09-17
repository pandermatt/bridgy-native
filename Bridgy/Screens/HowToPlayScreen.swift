import BridgyEngine
import SwiftUI

/// The rules, with a small board that plays itself through an example.
struct HowToPlayScreen: View {
    @Environment(AppModel.self) private var model
    @State private var demo = DemoBoard()

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    DemoBoardView(state: demo.state, settings: model.settings)
                        .frame(maxWidth: 260)
                        .frame(height: 260)
                        .frame(maxWidth: .infinity)
                    Text(demo.caption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .animation(.default, value: demo.caption)
                }
                .padding(.vertical, 8)
            }

            Section {
                rule("Two grids, interleaved", "square.grid.3x3", """
                Blue owns one grid of dots, red the other. They overlap so that every bridge blue \
                could build crosses exactly one bridge red could build.
                """)
                rule("Join your own dots", "hand.tap", """
                Tap the gap between two of your dots to bridge them. Taking a gap also denies it to \
                your opponent, so every move builds and blocks at once.
                """)
                rule("Cross the board", "arrow.up.and.down", """
                Blue moves first and needs an unbroken chain from top to bottom. Red needs one from \
                left to right.
                """)
                rule("Somebody always wins", "checkmark", """
                There are no draws. When the board fills, exactly one player has crossed it — and it \
                cannot be both, because their bridges would have to cross.
                """)
            }
        }
        .navigationTitle("How to Play")
        .task { await demo.run() }
    }

    private func rule(_ title: String, _ symbol: String, _ body: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
        .labelStyle(.titleAndIcon)
        .padding(.vertical, 4)
    }
}

/// A tiny self-playing game, so the rules have something to point at.
@MainActor
@Observable
final class DemoBoard {
    private(set) var state = GameState(size: 4)
    private(set) var caption = "Blue is trying to get from the top edge to the bottom."

    func run() async {
        let blue = ShortestPathEngine(strategy: .balanced, tieBreak: .longestConnection)
        let red = GreedyEngine(strategy: .balanced)
        var rng = SeededRandomNumberGenerator(seed: 42)
        while !Task.isCancelled {
            if state.isOver {
                caption = "\(state.winner!.displayName) got across. Starting again…"
                try? await Task.sleep(for: .seconds(2.2))
                state = GameState(size: 4)
                caption = "Blue is trying to get from the top edge to the bottom."
                continue
            }
            let engine: any Engine = state.current == .blue ? blue : red
            if let move = engine.chooseMove(in: state, rng: &rng) {
                state.apply(move)
            }
            try? await Task.sleep(for: .milliseconds(650))
        }
    }
}

/// Read-only board, for the demo.
struct DemoBoardView: View {
    let state: GameState
    let settings: AppSettings

    var body: some View {
        GeometryReader { proxy in
            let geometry = BoardGeometry(
                board: state.board,
                rect: CGRect(origin: .zero, size: proxy.size)
            )
            Canvas { context, _ in
                let radius = geometry.dotRadius
                for player in Player.allCases {
                    var dots = Path()
                    for dot in geometry.dots(for: player) {
                        let centre = geometry.point(of: dot)
                        dots.addEllipse(in: CGRect(
                            x: centre.x - radius, y: centre.y - radius,
                            width: radius * 2, height: radius * 2
                        ))
                    }
                    context.fill(dots, with: .color(settings.colorway.color(for: player).opacity(0.45)))

                    var edges = Path()
                    for cell in 0..<state.board.cellCount where state.cells[cell] == player {
                        let (from, to) = geometry.endpoints(of: state.board.move(at: cell), for: player)
                        edges.move(to: from)
                        edges.addLine(to: to)
                    }
                    context.stroke(
                        edges,
                        with: .color(settings.colorway.color(for: player)),
                        style: StrokeStyle(lineWidth: geometry.lineWidth, lineCap: .round)
                    )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
