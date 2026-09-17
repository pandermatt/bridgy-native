#if os(visionOS)
import BridgyEngine
import RealityKit
import Spatial
import SwiftUI
import TabletopKit

/// The board as a stretch of water in the room, with bridges you carry onto it.
///
/// The `TabletopGame` has to exist before the view body runs — `.tabletopGame`
/// takes it, not a binding to it — so the whole table is built in `init` rather
/// than inside the `RealityView` closure.
struct ImmersiveBoardView: View {
    @State private var table: TabletopBoard
    @State private var rules: BridgyRules

    init(configuration: GameConfiguration, theme: BoardTheme, style: BoardStyle) {
        let board = Board(size: configuration.size)
        let table = TabletopBoardBuilder(board: board, theme: theme, style: style).build()
        _table = State(initialValue: table)
        _rules = State(
            initialValue: BridgyRules(
                board: board,
                seats: [.blue: configuration.blue, .red: configuration.red],
                slots: table.slots,
                pieces: table.pieces
            )
        )
    }

    var body: some View {
        RealityView { content in
            // Anchored to the head rather than placed at a world coordinate. An
            // immersive space's origin is not somewhere to rely on — absolute
            // positions put the table underfoot or behind the viewer — whereas
            // "an arm's length ahead of wherever you are" is what this means.
            //
            // `.once` so it is set down at the start and stays put, rather than
            // following the head around like a HUD. Anchoring to a real surface
            // comes later; a fixed pose is the part the simulator can exercise.
            let anchor = AnchorEntity(.head)
            anchor.anchoring.trackingMode = .once
            table.root.position = SIMD3(0, -0.24, -1.05)
            anchor.addChild(table.root)
            content.add(anchor)
        }
        .tabletopGame(table.game, parent: table.root) { _ in
            BridgeInteraction(gaps: rules.gaps)
        }
        .task {
            rules.attach(to: table.game)
            // A script cannot pinch, so this drives the human side when asked:
            //   simctl spawn <device> defaults write <bundle> BridgyAutoPlay -bool YES
            guard UserDefaults.standard.bool(forKey: "BridgyAutoPlay") else { return }
            while !Task.isCancelled, !rules.state.isOver {
                try? await Task.sleep(for: .milliseconds(700))
                rules.simulateDrop()
            }
        }
    }
}

/// Keeps a carried bridge honest: while it is in the air the only places it will
/// settle are the gaps the engine says are legal for its owner right now.
///
/// This is the nicest thing TabletopKit gives us here — the rule is felt in the
/// drag rather than reported after it.
struct BridgeInteraction: TabletopInteraction.Delegate {
    let gaps: PlayableGaps

    /// Keeps a carried bridge honest: while it is in the air the only places it
    /// will settle are the gaps the engine says are legal for its owner right
    /// now. This is the nicest thing TabletopKit gives us here — the rule is
    /// felt in the drag rather than reported after it.
    func update(interaction: TabletopInteraction) {
        guard interaction.value.phase == .started else { return }
        let destinations = gaps.destinations(forPiece: interaction.value.startingEquipmentID)
        guard !destinations.isEmpty else {
            // Not this side's turn, or the game is already decided.
            interaction.cancel()
            return
        }
        interaction.setConfiguration(
            .init(
                allowedDestinations: .restricted(destinations),
                hoverAlignment: .automatic(targets: [.proposedDestination])
            )
        )
    }
}

#endif
