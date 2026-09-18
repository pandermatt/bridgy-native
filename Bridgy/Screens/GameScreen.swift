import AppIntents
import BridgyEngine
import SwiftUI

/// The board, on the system background, with everything else in system chrome.
struct GameScreen: View {
    @Bindable var session: GameSession
    @Environment(AppModel.self) private var model
    @Binding var showingInspector: Bool
    /// The game just finished, as kept in the history, for the recap.
    @State private var finished: PlayedGame?
    @State private var analysing: PlayedGame?
    @State private var sharing = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// A sidebar symbol where the inspector is a sidebar; on iPhone it rises
    /// from the bottom as a sheet of statistics, so it gets a chart instead.
    private var inspectorSymbol: String {
        #if os(iOS)
        sizeClass == .compact ? "chart.bar.xaxis" : "sidebar.right"
        #else
        "sidebar.right"
        #endif
    }

    private var isWatching: Bool { session.configuration.isWatchOnly }

    var body: some View {
        @Bindable var settings = model.settings
        return content(settings: $settings)
            .padding(.horizontal)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .navigationTitle(title)
            .platformSubtitle(subtitle)
            .toolbar { actions(settings: $settings) }
            .gameScreenTitleDisplayMode()
            .modifier(GameFeedback(session: session, settings: model.settings, isWatching: isWatching))
            // Siri can see which game is on screen, so "what should I play here?" has an answer.
            .appEntityIdentifier(EntityIdentifier(for: GameEntity.self, identifier: session.id))
            .onAppear { session.begin() }
            .onDisappear { session.stop() }
            // No sheet over the board when a game ends: the finished board is
            // the payoff. The gold path draws in, and the actions sit under it.
            .onChange(of: session.state.winner, initial: true) { _, winner in
                guard winner != nil else { finished = nil; return }
                finished = model.history.record(session.state, configuration: session.configuration)
            }
            .sheet(item: $analysing) { game in
                ReplayView(record: game.record, names: game.names)
            }
            .sheet(isPresented: $sharing) {
                ShareGameSheet(
                    state: session.state,
                    configuration: session.configuration,
                    theme: model.settings.theme,
                    cap: model.settings.bridgeCap,
                    initialStyle: model.settings.boardStyle,
                    highlightsWinningPath: model.settings.highlightsWinningPath
                )
            }
    }

    @ViewBuilder
    private func content(settings: Bindable<AppSettings>) -> some View {
        VStack(spacing: 16) {
            board
            if session.state.isOver, session.reviewIndex == nil {
                gameOverBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                if model.settings.showHints, !session.state.isOver {
                    hintLine
                }
                if isWatching {
                    paceControls(settings: settings)
                }
                #if os(iOS)
                if !isWatching, session.configuration.soloHumanPlayer != nil, model.settings.showsSiriHintTip {
                    SiriTipView(intent: SuggestMoveIntent(), isVisible: settings.showsSiriHintTip)
                }
                #endif
            }
        }
        .animation(.smooth, value: session.state.isOver)
    }

    /// What to do with a finished game, in the order you'd want it: look at
    /// how it went, show it off, go again. One glass capsule holding three
    /// buttons, the way the tab bar holds its tabs, rather than three big
    /// bordered buttons competing with the board.
    private var gameOverBar: some View {
        HStack(spacing: 0) {
            gameOverButton("Analyse", "chart.xyaxis.line", prominent: true) { analysing = finished }
                .disabled(finished == nil)
            Divider().frame(height: 22)
            gameOverButton("Share", "square.and.arrow.up") { sharing = true }
            Divider().frame(height: 22)
            gameOverButton("Play Again", "arrow.clockwise") { session.restart() }
        }
        .padding(4)
        .gameOverGlass()
        .fixedSize()
    }

    private func gameOverButton(_ title: String, _ symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(prominent ? .semibold : .medium))
                .foregroundStyle(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var board: some View {
        if let reviewIndex = session.reviewIndex {
            reviewBoard(at: reviewIndex)
        } else {
            liveBoard
        }
    }

    /// An earlier position, drawn but not playable, with the way back on it.
    private func reviewBoard(at index: Int) -> some View {
        var past = GameState(board: session.board)
        for move in session.state.moves.prefix(index) { past.apply(move) }
        return VStack(spacing: 8) {
            Button {
                session.reviewIndex = nil
            } label: {
                Label("Move \(index) of \(session.state.moveCount) — Back to the Game", systemImage: "arrow.uturn.forward")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            BoardCanvas(
                state: past,
                theme: model.settings.theme,
                style: model.settings.boardStyle,
                cap: model.settings.bridgeCap,
                guideDots: true
            )
            .aspectRatio(1, contentMode: .fit)
        }
    }

    private var liveBoard: some View {
        ZoomableBoard(enabled: session.board.size > 12) {
            BoardView(session: session, settings: model.settings)
        }
        // Animating a board that changes fifteen times a second just stacks
        // superseded animations on top of an O(n²) redraw.
        .animation(isWatching ? nil : .smooth(duration: 0.18), value: session.state.moveCount)
    }

    /// Short enough to survive the toolbar on a phone; the goal moves to the
    /// subtitle, where "Your turn — top to…" used to be cut off.
    private var title: String {
        if let winner = session.state.winner {
            if session.configuration.soloHumanPlayer == winner { return "You win" }
            if let human = session.configuration.soloHumanPlayer, human != winner {
                return "\(session.configuration.seat(for: winner).displayName) wins"
            }
            return "\(winner.displayName) wins"
        }
        if session.isHumanTurn, !session.configuration.isLocalTwoPlayer { return "Your turn" }
        return session.statusText
    }

    private var subtitle: String {
        var parts = ["\(session.state.moveCount) moves"]
        if session.isHumanTurn, !session.configuration.isLocalTwoPlayer {
            parts.insert(session.state.current.goalDescription.capitalizedFirst, at: 0)
        }
        if isWatching, session.isPaused { parts.append("paused") }
        return parts.joined(separator: " · ")
    }

    /// Reads the session's cached figures. Computing them here is what used to
    /// put two breadth-first searches in the render path.
    private var hintLine: some View {
        HStack(spacing: 16) {
            ForEach(Player.allCases, id: \.self) { player in
                Label {
                    Text(movesLabel(for: player))
                } icon: {
                    Image(systemName: player.symbolName)
                        .foregroundStyle(model.settings.theme.color(for: player))
                }
                .font(.footnote)
            }
        }
        .foregroundStyle(.secondary)
        .opacity(session.readout.isStale ? 0.5 : 1)
    }

    private func movesLabel(for player: Player) -> String {
        let needed = player == .blue ? session.readout.blue : session.readout.red
        guard let needed else { return "\(player.displayName) cut off" }
        return "\(player.displayName) needs \(needed)"
    }

    // MARK: - Pace

    private func paceControls(settings: Bindable<AppSettings>) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Pace").font(.subheadline)
                Spacer()
                Text(paceLabel)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { settings.wrappedValue.watchPace.sliderPosition },
                    set: { settings.wrappedValue.watchPace.sliderPosition = $0 }
                ),
                in: WatchPace.sliderRange
            ) {
                Text("Pace")
            } minimumValueLabel: {
                Image(systemName: "tortoise")
            } maximumValueLabel: {
                Image(systemName: "hare")
            }
            .labelsHidden()

            Toggle("Let engines think fully", isOn: settings.watchPace.allowsFullThinking)
                .font(.subheadline)
        }
        .padding(.bottom, 4)
    }

    /// Honest about the rate actually being managed when the engines cannot keep
    /// up with the ask.
    private var paceLabel: String {
        let requested = model.settings.watchPace
        guard !requested.isInstant else { return requested.rateDescription }
        guard let achieved = session.achievedMovesPerSecond,
              achieved < requested.movesPerSecond * 0.8 else {
            return requested.rateDescription
        }
        return String(format: "%@ · managing %.1f", requested.rateDescription, achieved)
    }

    // MARK: - Toolbar

    /// Watch mode gets a media transport. "Restart" tucked in a menu is not what
    /// someone reaching for "stop" is looking for.
    ///
    /// The overflow menu is on both sides of that branch, because how the board
    /// is drawn is worth changing mid-game — most of all while watching, where
    /// the dot-less styles are the point — and Settings is a long way to go for
    /// it.
    @ToolbarContentBuilder
    private func actions(settings: Bindable<AppSettings>) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingInspector.toggle() } label: {
                Label("Game Details", systemImage: inspectorSymbol)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if isWatching {
                Button {
                    session.togglePause()
                } label: {
                    Label(session.isPaused ? "Play" : "Pause",
                          systemImage: session.isPaused ? "play.fill" : "pause.fill")
                }
                Button {
                    session.finish()
                    model.session = nil
                } label: {
                    Label("Stop", systemImage: "stop.fill")
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
                appearanceItems(settings: settings)
                if !isWatching {
                    Divider()
                    Button { session.restart() } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    Button { model.session = nil } label: {
                        Label("New Game", systemImage: "plus")
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }

    /// The same two choices Settings offers, reachable without leaving the game.
    /// These do persist — unlike the result sheet's picker, which only dresses
    /// the picture being shared.
    @ViewBuilder
    private func appearanceItems(settings: Bindable<AppSettings>) -> some View {
        // Each one is its own submenu. A Picker placed directly in a Menu is
        // rendered inline whatever its pickerStyle, which put three unlabelled
        // lists end to end and two entries called "Classic".
        Menu {
            Picker("Board Style", selection: settings.boardStyle) {
                ForEach(BoardStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
        } label: {
            Label("Board Style", systemImage: "square.grid.2x2")
        }

        Menu {
            Picker("Colours", selection: settings.theme) {
                ForEach(BoardTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
        } label: {
            Label("Colours", systemImage: "paintpalette")
        }

        Menu {
            Picker("Bridge Ends", selection: settings.bridgeCap) {
                ForEach(BridgeCap.allCases) { cap in
                    Text(cap.displayName).tag(cap)
                }
            }
        } label: {
            Label("Bridge Ends", systemImage: "capsule")
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


/// Haptics, kept out of the body so the type checker has less to chew on.
private struct GameFeedback: ViewModifier {
    let session: GameSession
    let settings: AppSettings
    let isWatching: Bool

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(trigger: session.state.moveCount) { _, _ in
                // Not while two computers play: a haptic fifteen times a second
                // is a vibration, not feedback.
                settings.hapticsEnabled && !isWatching
                    ? .impact(weight: .light, intensity: 0.7)
                    : nil
            }
            .sensoryFeedback(trigger: session.state.winner) { _, winner in
                settings.hapticsEnabled && winner != nil ? .success : nil
            }
    }
}

extension View {
    @ViewBuilder
    func gameScreenTitleDisplayMode() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

extension String {
    /// "top to bottom" → "Top to bottom".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

private extension View {
    /// The capsule the end-of-game actions share: Liquid Glass where there is
    /// some, the system glass material on visionOS.
    @ViewBuilder
    func gameOverGlass() -> some View {
        #if os(visionOS)
        glassBackgroundEffect(in: .capsule)
        #else
        glassEffect(.regular.interactive(), in: .capsule)
        #endif
    }
}
