import SwiftUI

/// Tabs on iPhone; a sidebar and detail on iPad and the Mac.
///
/// The research side outgrew tabs: on a big screen the Lab wants the room a
/// sidebar leaves it, and the game wants an inspector beside the board.
struct AppRoot: View {
    @Environment(AppModel.self) private var model
    @State private var showingWelcome = false
    @State private var tab: AppTab = .play
    @State private var boardSide: CGFloat = 320
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    #if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    #endif

    private var usesSidebar: Bool {
        #if os(iOS)
        sizeClass == .regular
        #else
        true
        #endif
    }

    var body: some View {
        Group {
            if usesSidebar { split } else { tabs }
        }
        // Read rather than wrapped in a GeometryReader: that reader fed one
        // number to the board sizer but proposed its own size to the whole
        // view, which is exactly the sort of thing that leaves a grouped
        // Form's section background measured a row short on macOS.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            boardSide = Self.boardSide(in: size, sidebar: usesSidebar)
        }
        .environment(\.availableBoardSide, boardSide)
        .welcomeCover(isPresented: $showingWelcome) {
            model.settings.hasSeenWelcome = true
            showingWelcome = false
        }
        .task {
            // First launch only. Bridg-It is obscure enough that landing
            // straight on a lattice of dots explains nothing.
            if !model.settings.hasSeenWelcome { showingWelcome = true }
            #if os(visionOS)
            // The visionOS simulator takes gaze and pinch, not taps, so
            // there is no way to press the button from a script. This lets
            // a launch open the table directly:
            //   simctl launch <device> <bundle> -BridgyOpenTable YES
            if UserDefaults.standard.bool(forKey: "BridgyOpenTable") {
                await openImmersiveSpace(id: BridgyApp.tableSpace)
            }
            #endif
        }
    }

    private var tabs: some View {
        TabView(selection: tabSelection) {
            Tab("Play", systemImage: "play.circle", value: AppTab.play) {
                PlayTab()
            }
            Tab("Lab", systemImage: "flask", value: AppTab.lab) {
                NavigationStack { TournamentScreen() }
            }
            Tab("Rules", systemImage: "questionmark.circle", value: AppTab.rules) {
                NavigationStack { HowToPlayScreen() }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsScreen() }
            }
        }
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
    }

    private var split: some View {
        NavigationSplitView {
            List(selection: Binding<AppTab?>(get: { tab }, set: { if let new = $0 { tabSelection.wrappedValue = new } })) {
                Section {
                    ForEach(AppTab.sidebar) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                if !model.agents.agents.isEmpty || model.training.isRunning {
                    Section("Agents") {
                        ForEach(model.agents.agents) { agent in
                            Label(agent.name, systemImage: "brain")
                        }
                        .selectionDisabled()
                    }
                }
            }
            .navigationTitle("Bridgy")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch tab {
            case .play: PlayTab()
            case .lab: NavigationStack { TournamentScreen() }
            case .agents: NavigationStack { TrainingScreen(run: model.training) }
            case .rules: NavigationStack { HowToPlayScreen() }
            case .settings: NavigationStack { SettingsScreen() }
            }
        }
    }

    /// Selecting a tab goes through here rather than through a plain `$tab` so
    /// that re-tapping Play while Play is already up is caught too — `onChange`
    /// never fires for that, and "Play always lands on setup" is the point.
    ///
    /// A game left running behind another tab would keep thinking, and coming
    /// back mid-move is disorienting. Parking it stops the work, keeps the
    /// position, and offers it on the setup screen as Continue.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { tab },
            set: { selected in
                if tab == .play || selected == .play { model.parkSession() }
                tab = selected
            }
        )
    }

    /// Roughly what the board will get once the bars, sidebar and status line
    /// have taken their share. Only used to decide how large a board stays
    /// tappable.
    private static func boardSide(in size: CGSize, sidebar: Bool) -> CGFloat {
        let width = size.width - (sidebar ? 240 : 0)
        return max(120, min(width - 32, size.height - 280))
    }
}

enum AppTab: String, Hashable, Identifiable {
    case play, lab, agents, rules, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .play: "Play"
        case .lab: "Lab"
        case .agents: "Agents"
        case .rules: "Rules"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .play: "play.circle"
        case .lab: "flask"
        case .agents: "brain.head.profile"
        case .rules: "questionmark.circle"
        case .settings: "gearshape"
        }
    }

    /// The Mac keeps Settings in its own window, under the app menu.
    static var sidebar: [AppTab] {
        #if os(macOS)
        [.play, .lab, .agents, .rules]
        #else
        [.play, .lab, .agents, .rules, .settings]
        #endif
    }
}

/// Shows the board when a game is in progress, and the setup form otherwise.
///
/// The inspector hangs off the navigation stack, not the screen inside it:
/// attached inside, it took the navigation bar — title, toolbar and all —
/// away with it.
struct PlayTab: View {
    @Environment(AppModel.self) private var model
    @State private var showingInspector = PlayTab.inspectorByDefault

    private static var inspectorByDefault: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            if let session = model.session {
                GameScreen(session: session, showingInspector: $showingInspector)
            } else {
                SetupScreen()
            }
        }
        .platformInspector(isPresented: Binding(
            get: { showingInspector && model.session != nil },
            set: { showingInspector = $0 }
        )) {
            if let session = model.session {
                GameInspector(session: session)
            }
        }
    }
}


private extension View {
    /// A full-screen cover where there is one, a sheet on macOS, which has no
    /// such thing. visionOS has to be named explicitly — it is not `os(iOS)`,
    /// so it was taking the macOS branch along with its hardcoded sizing.
    @ViewBuilder
    func welcomeCover(isPresented: Binding<Bool>, onContinue: @escaping () -> Void) -> some View {
        #if os(iOS) || os(visionOS)
        fullScreenCover(isPresented: isPresented) {
            WelcomeScreen(onContinue: onContinue)
        }
        #else
        sheet(isPresented: isPresented) {
            WelcomeScreen(onContinue: onContinue).frame(minWidth: 460, minHeight: 560)
        }
        #endif
    }
}
