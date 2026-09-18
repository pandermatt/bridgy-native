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
    @State private var tableAnchor: AnchorEntity?
    /// Where on the board it was grabbed, so a drag carries it without the board
    /// jumping to put its centre under your hand.
    @State private var grabOffset: SIMD3<Float>?
    private let theme: BoardTheme

    init(configuration: GameConfiguration, theme: BoardTheme, style: BoardStyle) {
        let board = Board(size: configuration.size)
        let table = TabletopBoardBuilder(board: board, theme: theme, style: style).build()
        self.theme = theme
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
        RealityView { content, attachments in
            // Onto a real table if the room has one: RealityKit finds a
            // horizontal surface classified as a table and the board is set down
            // resting on its own thickness. The simulator's rooms offer no such
            // surface, so there it falls through to `placeOnSomething()`.
            let onTable = AnchorEntity(
                .plane(.horizontal, classification: .table, minimumBounds: [0.35, 0.35])
            )
            table.root.position = SIMD3(0, Float(TabletopBoardBuilder.surfaceThickness / 2), 0)
            onTable.addChild(table.root)
            content.add(onTable)
            tableAnchor = onTable

            if let status = attachments.entity(for: StatusPanel.id) {
                // Beside the board on Across's far side, facing you. Above the far
                // shore it landed on top of the app's own window, which sits in
                // the same place in your view.
                status.position = SIMD3(Float(table.metrics.side) / 2 + 0.24, 0.1, -0.05)
                table.root.addChild(status)
            }
        } attachments: {
            Attachment(id: StatusPanel.id) {
                StatusPanel(rules: rules, theme: theme)
            }
        }
        .tabletopGame(table.game, parent: table.root) { _ in
            BridgeInteraction(gaps: rules.gaps)
        }
        // Pick the board up by its banks and set it down wherever suits — on a
        // coffee table, say. Bridges are TabletopKit's, so this is filtered to
        // the banks and never claims one.
        .gesture(
            DragGesture()
                .targetedToEntity(where: .has(BoardHandleComponent.self))
                .onChanged { value in
                    guard let parent = table.root.parent else { return }
                    let hand = value.convert(value.location3D, from: .local, to: parent)
                    let offset = grabOffset ?? table.root.position - hand
                    grabOffset = offset
                    table.root.position = hand + offset
                }
                .onEnded { _ in grabOffset = nil }
        )
        .task {
            rules.attach(to: table.game)
            await placeOnSomething()
            // A script cannot pinch, so this drives the human side when asked.
            // Off unless set:
            //   simctl spawn <device> defaults write <bundle> BridgyAutoPlay -bool YES
            guard UserDefaults.standard.bool(forKey: "BridgyAutoPlay") else { return }
            while !Task.isCancelled, !rules.state.isOver {
                try? await Task.sleep(for: .milliseconds(700))
                rules.simulateDrop()
            }
        }
    }
}

extension ImmersiveBoardView {
    /// Falls back to a spot in front of you when there is no table to find.
    ///
    /// A plane anchor that never resolves leaves the board nowhere at all, which
    /// is worse than a board in a sensible place. So it gets a moment to find a
    /// table and is otherwise set down low and ahead — roughly coffee-table
    /// height — to be dragged the rest of the way.
    @MainActor
    func placeOnSomething() async {
        for _ in 0..<20 {
            if tableAnchor?.isAnchored == true { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard let tableAnchor, !tableAnchor.isAnchored, let parent = tableAnchor.parent else { return }

        let ahead = AnchorEntity(.head)
        ahead.anchoring.trackingMode = .once
        table.root.removeFromParent()
        table.root.position = SIMD3(0, -0.43, -1.15)
        ahead.addChild(table.root)
        parent.addChild(ahead)
        tableAnchor.removeFromParent()
    }
}

/// Whose turn it is, or who won, floating over the far shore.
struct StatusPanel: View {
    static let id = "status"
    let rules: BridgyRules
    let theme: BoardTheme

    private var state: GameState { rules.state }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(theme.color(for: focus))
                    .frame(width: 16, height: 16)
                Text(headline)
                    .font(.title2.weight(.semibold))
            }
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if state.isOver {
                Button("Play Again") { rules.playAgain() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(minWidth: 320)
        .glassBackgroundEffect()
        .animation(.default, value: state.moveCount)
    }

    /// The side the panel is about: the winner once there is one, otherwise the
    /// side to move.
    private var focus: BoardSide { state.winner ?? state.current }

    private var headline: String {
        if let winner = state.winner {
            if rules.humanSide == winner { return "You crossed!" }
            return "\(winner.displayName) crossed"
        }
        if rules.isComputer(state.current) {
            return "\(state.current.displayName) is thinking…"
        }
        if rules.humanSide == state.current { return "Your move" }
        return "\(state.current.displayName) to move"
    }

    private var detail: String? {
        if state.isOver {
            return "\(state.moveCount) bridges built."
        }
        guard !rules.isComputer(state.current) else { return nil }
        return "Take a bridge from your pile and set it across a gap, \(state.current.goalDescription)."
    }
}

/// Keeps a carried bridge honest: while it is in the air the only places it will
/// settle are the gaps the engine says are legal for its owner right now.
///
/// This is the nicest thing TabletopKit gives us here — the rule is felt in the
/// drag rather than reported after it.
struct BridgeInteraction: TabletopInteraction.Delegate {
    let gaps: PlayableGaps

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
