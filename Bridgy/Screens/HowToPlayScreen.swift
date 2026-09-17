import BridgyEngine
import SwiftUI

/// The rules, with a small board that plays itself through an example.
struct HowToPlayScreen: View {
    @Environment(AppModel.self) private var model
    @State private var demo = DemoBoard()
    @State private var showingWelcome = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    // Always Classic: the rule beside this says "tap the gap
                    // between two of your dots", and the dot-less styles would
                    // leave nothing to point at. The theme still follows the
                    // user's, so the colours match the rest of the app.
                    BoardCanvas(
                        state: demo.state,
                        theme: model.settings.theme,
                        style: .classic,
                        cap: model.settings.bridgeCap
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 260)
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
                Button {
                    showingWelcome = true
                } label: {
                    Label("What is Bridg-It?", systemImage: "sparkles")
                }
            }

            Section {
                rule("Two grids, interleaved", "square.grid.3x3", """
                You own one grid of dots, your opponent the other. They overlap so that every \
                bridge you could build crosses exactly one of theirs.
                """)
                rule("Join your own dots", "hand.tap", """
                Tap the gap between two of your dots to bridge them. Taking a gap also denies it to \
                your opponent, so every move builds and blocks at once.
                """)
                rule("Cross the board", "arrow.up.and.down", """
                Down moves first and needs an unbroken chain from top to bottom. Across needs one \
                from left to right.
                """)
                rule("Somebody always wins", "checkmark", """
                There are no draws. When the board fills, exactly one player has crossed it — and it \
                cannot be both, because their bridges would have to cross.
                """)
            }
        }
        .navigationTitle("How to Play")
        .task { await demo.run() }
        .sheet(isPresented: $showingWelcome) {
            WelcomeScreen(onContinue: { showingWelcome = false })
        }
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
    static let opening = "Down is trying to get from the top edge to the bottom."

    private(set) var state = GameState(size: 4)
    private(set) var caption = DemoBoard.opening

    func run() async {
        let blue = ShortestPathEngine(strategy: .balanced, tieBreak: .longestConnection)
        let red = GreedyEngine(strategy: .balanced)
        var rng = SeededRandomNumberGenerator(seed: 42)
        while !Task.isCancelled {
            if state.isOver {
                caption = "\(state.winner!.displayName) got across. Starting again…"
                try? await Task.sleep(for: .seconds(2.2))
                state = GameState(size: 4)
                caption = DemoBoard.opening
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
