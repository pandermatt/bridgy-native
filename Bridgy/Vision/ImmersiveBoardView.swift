#if os(visionOS)
import ARKit
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
    /// Where on the board it was grabbed, so a drag carries it without the board
    /// jumping to put its centre under your hand.
    @State private var grabOffset: SIMD3<Float>?
    /// True until the person says where the board goes.
    @State private var placing = true
    /// Whether the game has been started on the table yet.
    @State private var attached = false
    @State private var onSurface = false
    @State private var tables = TableFinder()
    private let theme: BoardTheme

    /// Ahead and a little below eye level: about coffee-table height when
    /// sitting, and within reach.
    static let startPosition = SIMD3<Float>(0, -0.45, -1.0)

    init(
        configuration: GameConfiguration,
        theme: BoardTheme,
        style: BoardStyle,
        agentEngine: (UUID) -> (any Engine)? = { _ in nil }
    ) {
        let board = Board(size: configuration.size)
        let table = TabletopBoardBuilder(board: board, theme: theme, style: style).build()
        self.theme = theme
        _table = State(initialValue: table)
        _rules = State(
            initialValue: BridgyRules(
                board: board,
                seats: [.blue: configuration.blue, .red: configuration.red],
                slots: table.slots,
                pieces: table.pieces,
                agentEngine: agentEngine
            )
        )
    }

    var body: some View {
        RealityView { content, attachments in
            // Set once in front of you, then fixed in the room: a head anchor
            // that tracks only once. From there the person decides where it
            // goes; nothing is placed behind their back.
            let ahead = AnchorEntity(.head)
            ahead.anchoring.trackingMode = .once
            table.root.position = Self.startPosition
            ahead.addChild(table.root)
            content.add(ahead)
            table.setPlacing(true)

            let panelPosition = SIMD3<Float>(Float(table.metrics.side) / 2 + 0.24, 0.1, -0.05)
            if let status = attachments.entity(for: StatusPanel.id) {
                // Beside the board on Across's far side, facing you. Above the
                // far shore it landed on top of the app's own window.
                status.position = panelPosition
                status.isEnabled = false
                table.root.addChild(status)
            }
            if let panel = attachments.entity(for: PlacementPanel.id) {
                // Beside the board, where the status panel will be: above the
                // far shore it sat behind the app's own window.
                panel.position = panelPosition
                table.root.addChild(panel)
            }
        } update: { _, attachments in
            attachments.entity(for: StatusPanel.id)?.isEnabled = !placing
            attachments.entity(for: PlacementPanel.id)?.isEnabled = placing
        } attachments: {
            Attachment(id: StatusPanel.id) {
                StatusPanel(rules: rules, theme: theme) { startPlacing() }
            }
            Attachment(id: PlacementPanel.id) {
                PlacementPanel(onSurface: onSurface, place: place, reset: resetPosition)
            }
        }
        .tabletopGame(table.game, parent: table.root) { _ in
            BridgeInteraction(gaps: rules.gaps)
        }
        // Pick the board up by its shores and set it down wherever suits. A
        // simultaneous gesture, so TabletopKit's own input handling on the same
        // view cannot swallow it; bridges are paused while it runs.
        .simultaneousGesture(
            DragGesture()
                .targetedToEntity(where: .has(BoardHandleComponent.self))
                .onChanged { value in
                    guard let parent = table.root.parent else { return }
                    rules.gaps.setPaused(true)
                    let hand = value.convert(value.location3D, from: .local, to: parent)
                    let offset = grabOffset ?? table.root.position - hand
                    grabOffset = offset
                    moveBoard(to: hand + offset)
                }
                .onEnded { _ in
                    grabOffset = nil
                    if !placing { rules.gaps.setPaused(false) }
                }
        )
        .task { await tables.run() }
        .task { await runTestSeams() }
    }

    // MARK: - Placement

    /// Moves the board, in its parent's space, keeping it level — and onto a
    /// real surface when one is close underneath (on a device).
    private func moveBoard(to position: SIMD3<Float>) {
        table.root.position = position
        let world = table.root.position(relativeTo: nil)
        if let surface = tables.surface(under: world) {
            var snapped = world
            snapped.y = surface + Float(TabletopBoardBuilder.surfaceThickness / 2)
            table.root.setPosition(snapped, relativeTo: nil)
            onSurface = true
        } else {
            onSurface = false
        }
    }

    private func resetPosition() {
        table.root.position = Self.startPosition
        onSurface = false
    }

    /// Here: the board becomes solid, and the game starts — only now, so a
    /// computer that moves first doesn't play before you've found the board.
    private func place() {
        placing = false
        table.setPlacing(false)
        rules.gaps.setPaused(false)
        if !attached {
            attached = true
            rules.attach(to: table.game)
        }
    }

    private func startPlacing() {
        placing = true
        table.setPlacing(true)
        rules.gaps.setPaused(true)
    }

    /// The visionOS simulator takes gaze and pinch, not scripted touches, so
    /// these let a launch drive the same paths a person would.
    ///   -BridgyPlaceAt "0.3,-0.4,-1.2"   move there (same code as a drag), then place
    ///   BridgyAutoPlay (defaults)         place where it is and play the human side
    private func runTestSeams() async {
        let defaults = UserDefaults.standard
        if let spec = defaults.string(forKey: "BridgyPlaceAt") {
            let parts = spec.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
            try? await Task.sleep(for: .seconds(2))
            if parts.count == 3 { moveBoard(to: SIMD3(parts[0], parts[1], parts[2])) }
            try? await Task.sleep(for: .seconds(1))
            place()
        }
        guard defaults.bool(forKey: "BridgyAutoPlay") else { return }
        if placing {
            try? await Task.sleep(for: .seconds(1))
            place()
        }
        while !Task.isCancelled, !rules.state.isOver {
            try? await Task.sleep(for: .milliseconds(700))
            rules.simulateDrop()
        }
    }
}

/// "Where should the board go?" — shown over the far shore while placing.
struct PlacementPanel: View {
    static let id = "placement"
    let onSurface: Bool
    let place: () -> Void
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Where should the board go?")
                .font(.title2.weight(.semibold))
            Text(onSurface
                 ? "On the table. Tap Place Here, or keep moving it."
                 : "Pinch a shore and drag the board to a table or anywhere comfortable, then tap Place Here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 12) {
                Button("Reset", systemImage: "arrow.counterclockwise", action: reset)
                Button("Place Here", systemImage: "checkmark", action: place)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .glassBackgroundEffect()
    }
}

/// Horizontal surfaces in the room, for the board to settle on.
///
/// Plane detection needs a device and the person's permission; in the
/// simulator, or if they decline, there are simply no surfaces and placement is
/// free.
@MainActor
@Observable
final class TableFinder {
    private struct Surface {
        let transform: simd_float4x4
        let width: Float
        let depth: Float
    }
    @ObservationIgnored private var surfaces: [UUID: Surface] = [:]
    @ObservationIgnored private let session = ARKitSession()
    private static let snapDistance: Float = 0.12

    func run() async {
        guard PlaneDetectionProvider.isSupported else { return }
        let provider = PlaneDetectionProvider(alignments: [.horizontal])
        do {
            try await session.run([provider])
        } catch {
            return
        }
        for await update in provider.anchorUpdates {
            let anchor = update.anchor
            switch update.event {
            case .removed:
                surfaces[anchor.id] = nil
            default:
                surfaces[anchor.id] = Surface(
                    transform: anchor.originFromAnchorTransform,
                    width: anchor.geometry.extent.width,
                    depth: anchor.geometry.extent.height
                )
            }
        }
    }

    /// The height of a surface under `point` (world space), if one is within
    /// snapping distance.
    func surface(under point: SIMD3<Float>) -> Float? {
        var best: Float?
        for surface in surfaces.values {
            let local = surface.transform.inverse * SIMD4(point, 1)
            guard abs(local.x) <= surface.width / 2, abs(local.z) <= surface.depth / 2 else { continue }
            let height = surface.transform.columns.3.y
            guard abs(point.y - height) < Self.snapDistance else { continue }
            if best.map({ abs(point.y - height) < abs(point.y - $0) }) ?? true { best = height }
        }
        return best
    }
}

/// Whose turn it is, or who won, floating over the far shore.
struct StatusPanel: View {
    static let id = "status"
    let rules: BridgyRules
    let theme: BoardTheme
    var moveBoard: () -> Void = {}

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
            HStack(spacing: 12) {
                Button("Move Board", systemImage: "arrow.up.and.down.and.arrow.left.and.right", action: moveBoard)
                if state.isOver {
                    Button("Play Again") { rules.playAgain() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 4)
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
