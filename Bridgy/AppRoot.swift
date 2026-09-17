import SwiftUI

/// Chooses the navigation shape: a stack on iPhone, a sidebar everywhere else.
struct AppRoot: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Destination] = []
    @State private var selection: Destination? = .play

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        #if os(macOS)
        // Every view here is flexible, so SwiftUI has no ideal size to size the
        // window from. Give it a floor rather than let it open arbitrarily small.
        splitLayout
            .frame(minWidth: 760, minHeight: 580)
        #else
        if sizeClass == .regular { splitLayout } else { stackLayout }
        #endif
    }

    private var stackLayout: some View {
        NavigationStack(path: $path) {
            HomeScreen(
                onSelect: { path.append($0) },
                onResume: {
                    model.resumeGame()
                    path.append(.play)
                },
                onNewGame: {
                    model.session = nil
                    path.append(.play)
                }
            )
            .navigationDestination(for: Destination.self) { destination in
                view(for: destination) { path = [.play] }
                    .navigationTitle(destination.title)
            }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $selection) { destination in
                Label(destination.title, systemImage: destination.symbolName)
                    .tag(destination)
            }
            .scrollContentBackground(.hidden)
            .background { BackdropView(backdrop: model.settings.backdrop) }
            .navigationTitle("Bridgy")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        } detail: {
            NavigationStack {
                view(for: selection ?? .play) { selection = .play }
                    .background { BackdropView(backdrop: model.settings.backdrop) }
            }
        }
    }

    /// `onStarted` lets each layout move to the board in its own way.
    @ViewBuilder
    private func view(for destination: Destination, onStarted: @escaping () -> Void) -> some View {
        switch destination {
        case .play:
            if let session = model.session {
                GameScreen(session: session)
            } else {
                NewGameScreen(configuration: playConfiguration) { configuration in
                    model.startGame(configuration)
                    onStarted()
                }
            }
        case .watch:
            if let session = model.session, session.configuration.isWatchOnly {
                GameScreen(session: session)
            } else {
                NewGameScreen(configuration: model.configuration, watchOnly: true) { configuration in
                    model.startGame(configuration)
                    onStarted()
                }
            }
        case .tournament:
            TournamentScreen()
        case .howToPlay:
            HowToPlayScreen()
        case .settings:
            SettingsScreen()
        case .about:
            AboutScreen()
        }
    }

    /// Never open New Game preset to two computers; that is what Watch is for.
    private var playConfiguration: GameConfiguration {
        var configuration = model.configuration
        if configuration.isWatchOnly { configuration.blue = .human }
        return configuration
    }
}
