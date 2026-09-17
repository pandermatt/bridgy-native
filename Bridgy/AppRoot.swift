import SwiftUI

/// One `TabView` for every platform.
///
/// `.sidebarAdaptable` makes this a tab bar on iPhone and a sidebar on iPad and
/// Mac, which replaces the size-class branch this used to carry.
struct AppRoot: View {
    var body: some View {
        GeometryReader { proxy in
            TabView {
                Tab("Play", systemImage: "play.circle") {
                    PlayTab()
                }
                Tab("Tournament", systemImage: "trophy") {
                    NavigationStack { TournamentScreen() }
                }
                Tab("Rules", systemImage: "questionmark.circle") {
                    NavigationStack { HowToPlayScreen() }
                }
                Tab("Settings", systemImage: "gearshape") {
                    NavigationStack { SettingsScreen() }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .environment(\.availableBoardSide, boardSide(in: proxy.size))
            #if os(iOS)
            .tabBarMinimizeBehavior(.onScrollDown)
            #endif
        }
    }

    /// Roughly what the board will get once the bars and status line have taken
    /// their share. Only used to decide how large a board stays tappable.
    private func boardSide(in size: CGSize) -> CGFloat {
        max(120, min(size.width - 32, size.height - 280))
    }
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
