import SwiftUI

/// One `TabView` for every platform.
///
/// `.sidebarAdaptable` makes this a tab bar on iPhone and a sidebar on iPad and
/// Mac, which replaces the size-class branch this used to carry.
struct AppRoot: View {
    @Environment(AppModel.self) private var model
    @State private var showingWelcome = false
    @State private var tab: AppTab = .play
    @State private var boardSide: CGFloat = 320

    var body: some View {
            TabView(selection: tabSelection) {
                Tab("Play", systemImage: "play.circle", value: AppTab.play) {
                    PlayTab()
                }
                Tab("Tournament", systemImage: "trophy", value: AppTab.tournament) {
                    NavigationStack { TournamentScreen() }
                }
                Tab("Rules", systemImage: "questionmark.circle", value: AppTab.rules) {
                    NavigationStack { HowToPlayScreen() }
                }
                Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                    NavigationStack { SettingsScreen() }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            // Read rather than wrapped in a GeometryReader: that reader fed one
            // number to the board sizer but proposed its own size to the whole
            // TabView, which is exactly the sort of thing that leaves a grouped
            // Form's section background measured a row short on macOS.
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                boardSide = Self.boardSide(in: size)
            }
            .environment(\.availableBoardSide, boardSide)
            #if os(iOS)
            .tabBarMinimizeBehavior(.onScrollDown)
            #endif
            .welcomeCover(isPresented: $showingWelcome) {
                model.settings.hasSeenWelcome = true
                showingWelcome = false
            }
            .task {
                // First launch only. Bridg-It is obscure enough that landing
                // straight on a lattice of dots explains nothing.
                if !model.settings.hasSeenWelcome { showingWelcome = true }
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

    /// Roughly what the board will get once the bars and status line have taken
    /// their share. Only used to decide how large a board stays tappable.
    private static func boardSide(in size: CGSize) -> CGFloat {
        max(120, min(size.width - 32, size.height - 280))
    }
}

enum AppTab: Hashable {
    case play, tournament, rules, settings
}

/// Shows the board when a game is in progress, and the setup form otherwise.
struct PlayTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            if let session = model.session {
                GameScreen(session: session)
            } else {
                SetupScreen()
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
