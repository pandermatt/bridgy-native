import BridgyEngine
import SwiftUI

/// The board, a status line above it and a glass bar of actions below.
struct GameScreen: View {
    @Bindable var session: GameSession
    @Environment(AppModel.self) private var model
    @State private var showingResult = false

    var body: some View {
        VStack(spacing: 12) {
            statusCard
            Spacer(minLength: 0)
            ZoomableBoard(enabled: session.board.size > 12) {
                BoardView(session: session, settings: model.settings)
            }
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .background { BackdropView(backdrop: model.settings.backdrop) }
        .safeAreaBar(edge: .bottom) { actionBar }
        .sensoryFeedback(trigger: session.state.moveCount) { _, _ in
            model.settings.hapticsEnabled ? .impact(weight: .light, intensity: 0.7) : nil
        }
        .sensoryFeedback(trigger: session.state.winner) { _, winner in
            model.settings.hapticsEnabled && winner != nil ? .success : nil
        }
        .onAppear { session.begin() }
        .onDisappear { session.stop() }
        .onChange(of: session.state.winner) { _, winner in
            showingResult = winner != nil
        }
        .sheet(isPresented: $showingResult) { resultSheet }
        .navigationTitle("Bridgy")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                if session.isThinking {
                    ProgressView().controlSize(.small)
                } else {
                    Circle()
                        .fill(model.settings.colorway.color(for: session.state.current))
                        .frame(width: 12, height: 12)
                }
                Text(session.statusText)
                    .font(.headline)
                Spacer(minLength: 0)
                Text("\(session.state.moveCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(session.state.moveCount) moves played")
            }
            if model.settings.showHints, !session.state.isOver {
                HStack(spacing: 16) {
                    ForEach(Player.allCases, id: \.self) { player in
                        Label {
                            Text(movesLabel(for: player))
                        } icon: {
                            Image(systemName: player.symbolName)
                                .foregroundStyle(model.settings.colorway.color(for: player))
                        }
                        .font(.caption)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 16)
    }

    private func movesLabel(for player: Player) -> String {
        guard let moves = session.movesToWin(for: player) else { return "\(player.displayName) is cut off" }
        return "\(player.displayName) needs \(moves)"
    }

    // MARK: - Actions

    private var actionBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if session.configuration.isWatchOnly {
                    action(session.isPaused ? "Play" : "Pause",
                           systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                        session.togglePause()
                    }
                } else {
                    action("Undo", systemImage: "arrow.uturn.backward", isEnabled: session.canUndo) {
                        session.undo()
                    }
                    action("Hint", systemImage: "lightbulb", isEnabled: session.isHumanTurn) {
                        session.requestHint()
                    }
                }
                action("Restart", systemImage: "arrow.clockwise") { session.restart() }
                action("New", systemImage: "plus") { model.session = nil }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func action(
        _ title: String,
        systemImage: String,
        isEnabled: Bool = true,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 44, height: 40)
        }
        .buttonStyle(.glass)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }

    // MARK: - Result

    private var resultSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "trophy")
                .font(.system(size: 48))
                .foregroundStyle(winnerColor)
            VStack(spacing: 6) {
                Text(resultTitle)
                    .font(.title2.bold())
                Text("\(session.state.moveCount) moves")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                Button {
                    showingResult = false
                    session.restart()
                } label: {
                    Label("Play again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)

                Button {
                    showingResult = false
                    model.session = nil
                } label: {
                    Label("Change setup", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
        .presentationDetents([.medium])
        .presentationBackground(.regularMaterial)
    }

    private var winnerColor: Color {
        guard let winner = session.state.winner else { return .secondary }
        return model.settings.colorway.color(for: winner)
    }

    private var resultTitle: String {
        guard let winner = session.state.winner else { return "Game over" }
        switch session.configuration.seat(for: winner) {
        case .human where session.configuration.soloHumanPlayer != nil:
            return "You win"
        default:
            return "\(winner.displayName) wins"
        }
    }
}

/// Wraps the board so very large ones can be pinched and panned.
struct ZoomableBoard<Content: View>: View {
    let enabled: Bool
    @ViewBuilder var content: Content

    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        if enabled {
            GeometryReader { proxy in
                let base = min(proxy.size.width, proxy.size.height)
                let side = base * min(max(zoom * pinch, 1), 5)
                ScrollView([.horizontal, .vertical]) {
                    content
                        .frame(width: side, height: side)
                }
                .scrollBounceBehavior(.basedOnSize)
                .simultaneousGesture(
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in
                            zoom = min(max(zoom * value.magnification, 1), 5)
                        }
                )
            }
        } else {
            content
        }
    }
}
