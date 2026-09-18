import AppIntents
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
                    // Always Classic, always rounded: the rule beside this says
                    // "tap the gap between two of your dots", and a dot-less
                    // style would leave nothing to point at. Square ends are the
                    // same thing one step down — a stylistic choice turning hard
                    // corners in what is meant to be a neutral explanation. The
                    // theme still follows the user's, so the colours match the
                    // rest of the app; only the shape is fixed.
                    BoardCanvas(
                        state: demo.state,
                        theme: model.settings.theme,
                        style: .classic,
                        cap: .rounded
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
                #if os(iOS)
                SiriTipView(intent: ExplainRulesIntent())
                #else
                Label("Ask Siri to explain the rules of Bridgy.", systemImage: "mic")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #endif
            }

            Section {
                ForEach(Rules.all) { item in
                    rule(item.title, item.symbol, item.body)
                }
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
            // A fixed column, so every title starts at the same place however
            // wide its symbol is.
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 26)
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

/// The rules, once, for this screen and for Siri to read out.
enum Rules {
    struct Item: Identifiable {
        var id: String { title }
        let title: String
        let symbol: String
        let body: String
    }

    static let all: [Item] = [
        Item(title: "Two grids, interleaved", symbol: "square.grid.3x3", body: """
        You own one grid of dots, your opponent the other. They overlap so that every \
        bridge you could build crosses exactly one of theirs.
        """),
        Item(title: "Join your own dots", symbol: "hand.tap", body: """
        Tap the gap between two of your dots to bridge them. Taking a gap also denies it to \
        your opponent, so every move builds and blocks at once.
        """),
        Item(title: "Cross the board", symbol: "arrow.up.and.down", body: """
        Down moves first and needs an unbroken chain from top to bottom. Across needs one \
        from left to right.
        """),
        Item(title: "Somebody always wins", symbol: "checkmark", body: """
        There are no draws. When the board fills, exactly one player has crossed it — and it \
        cannot be both, because their bridges would have to cross.
        """)
    ]

    /// The rules as Siri says them: plain sentences, no headings.
    static var spoken: String {
        "Bridgy is Bridg-It, a game for two. " + all.map(\.body).joined(separator: " ")
    }
}
