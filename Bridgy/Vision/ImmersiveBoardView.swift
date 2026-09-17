#if os(visionOS)
import BridgyEngine
import RealityKit
import Spatial
import SwiftUI
import TabletopKit

/// The board as a table in the room.
///
/// The `TabletopGame` has to exist before the view body runs — `.tabletopGame`
/// takes it, not a binding to it — so the whole table is built in `init` rather
/// than inside the `RealityView` closure.
struct ImmersiveBoardView: View {
    @State private var table: TabletopBoard

    init(board: Board, theme: BoardTheme, style: BoardStyle) {
        _table = State(
            initialValue: TabletopBoardBuilder(board: board, theme: theme, style: style).build()
        )
    }

    var body: some View {
        RealityView { content in
            // Anchored to the head rather than placed at a world coordinate.
            // An immersive space's origin is not somewhere you can rely on —
            // absolute positions put the table underfoot or behind the viewer —
            // whereas "half a metre down, an arm's length ahead of wherever you
            // are" is exactly what this wants to mean.
            //
            // `.once` so it is dropped in place at the start and then stays put,
            // rather than following the head around like a HUD.
            let anchor = AnchorEntity(.head)
            anchor.anchoring.trackingMode = .once
            table.root.position = SIMD3(0, -0.24, -1.05)
            anchor.addChild(table.root)
            content.add(anchor)
        }
        .tabletopGame(table.game, parent: table.root)
        .task { await demonstrate() }
    }

    /// Phase 2 has no interaction yet, so two engines play and the table fills
    /// in. It is the cheapest thing that proves TabletopKit renders at all.
    private func demonstrate() async {
        var state = GameState(size: table.metrics.board.size)
        var rng = SeededRandomNumberGenerator(seed: 42)
        let down = ShortestPathEngine(strategy: .balanced)
        let across = GreedyEngine(strategy: .balanced)

        table.show(state)
        while !state.isOver, !Task.isCancelled {
            let engine: any Engine = state.current == .blue ? down : across
            guard let move = engine.chooseMove(in: state, rng: &rng) else { break }
            state.apply(move)
            table.show(state)
            try? await Task.sleep(for: .milliseconds(350))
        }
    }
}
#endif
