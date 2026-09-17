import BridgyEngine
import SwiftUI

/// The board, on the system background, with everything else in system chrome.
struct GameScreen: View {
    @Bindable var session: GameSession
    @Environment(AppModel.self) private var model
    @State private var showingResult = false

    var body: some View {
        @Bindable var settings = model.settings
        VStack(spacing: 16) {
            ZoomableBoard(enabled: session.board.size > 12) {
                BoardView(session: session, settings: model.settings)
            }

            if model.settings.showHints, !session.state.isOver {
                hintLine
            }

            if session.configuration.isWatchOnly {
                Form { WatchPaceControls(pace: $settings.watchPace) }
                    .formStyle(.grouped)
                    .frame(maxHeight: 220)
                    .scrollDisabled(true)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .navigationTitle(session.statusText)
        .navigationSubtitle(subtitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { actions }
        .sensoryFeedback(trigger: session.state.moveCount) { _, _ in
            model.settings.hapticsEnabled ? .impact(weight: .light, intensity: 0.7) : nil
        }
        .sensoryFeedback(trigger: session.state.winner) { _, winner in
            model.settings.hapticsEnabled && winner != nil ? .success : nil
        }
        .onAppear { session.begin() }
        .onDisappear { session.stop() }
        .onChange(of: session.state.winner) { _, winner in showingResult = winner != nil }
        .onChange(of: model.settings.watchPace) { _, _ in session.paceChanged() }
        .alert(resultTitle, isPresented: $showingResult) {
            Button("Play Again") { session.restart() }
            Button("Change Setup") { model.session = nil }
            Button("Close", role: .cancel) {}
        } message: {
            Text("\(session.state.moveCount) moves.")
        }
    }

    private var subtitle: String {
        var parts = ["\(session.state.moveCount) moves"]
        if session.configuration.isWatchOnly, session.isPaused { parts.append("paused") }
        return parts.joined(separator: " · ")
    }

    private var hintLine: some View {
        HStack(spacing: 16) {
            ForEach(Player.allCases, id: \.self) { player in
                Label {
                    Text(movesLabel(for: player))
                } icon: {
                    Image(systemName: player.symbolName)
                        .foregroundStyle(model.settings.colorway.color(for: player))
                }
                .font(.footnote)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func movesLabel(for player: Player) -> String {
        guard let moves = session.movesToWin(for: player) else { return "\(player.displayName) cut off" }
        return "\(player.displayName) needs \(moves)"
    }

    // MARK: - Toolbar

    /// The board lives inside a tab, and a bottom bar would fight the tab bar
    /// for the same strip of screen, so everything goes in the navigation bar:
    /// the one or two actions you reach for constantly, and the rest behind an
    /// overflow menu.
    @ToolbarContentBuilder
    private var actions: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if session.configuration.isWatchOnly {
                Button {
                    session.togglePause()
                } label: {
                    Label(session.isPaused ? "Play" : "Pause",
                          systemImage: session.isPaused ? "play.fill" : "pause.fill")
                }
            } else {
                Button { session.undo() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!session.canUndo)

                Button { session.requestHint() } label: {
                    Label("Hint", systemImage: "lightbulb")
                }
                .disabled(!session.isHumanTurn)
            }

            Menu {
                Button { session.restart() } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                Button { model.session = nil } label: {
                    Label("New Game", systemImage: "plus")
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }

    private var resultTitle: String {
        guard let winner = session.state.winner else { return "Game Over" }
        if session.configuration.soloHumanPlayer == winner { return "You Win" }
        if session.configuration.soloHumanPlayer != nil { return "\(winner.displayName) Wins" }
        return "\(winner.displayName) Wins"
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
                    content.frame(width: side, height: side)
                }
                .scrollBounceBehavior(.basedOnSize)
                .simultaneousGesture(
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in zoom = min(max(zoom * value.magnification, 1), 5) }
                )
            }
        } else {
            content
        }
    }
}
