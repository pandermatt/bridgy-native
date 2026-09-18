import AppIntents
import BridgyEngine
import SwiftUI

@main
struct BridgyApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        // Siri, Shortcuts and the on-screen entities reach the app through this.
        AppDependencyManager.shared.add(dependency: model)
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(model)
                .task { model.prepareAudio() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Game") { model.session = nil }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Move") { model.session?.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(model.session?.canUndo != true)
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(AppTab.sidebar.prefix(4).enumerated()), id: \.element) { index, tab in
                    Button(tab.title) { model.requestedTab = tab }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
            CommandMenu("Lab") {
                Button("Show Experiments") { model.requestedTab = .lab }
                Button("Stop Experiment") { model.runner.stop(library: model.library) }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.runner.isRunning)
                Divider()
                Button("Train an Agent…") { model.requestedTab = .agents }
            }
            CommandMenu("Game") {
                Button("Restart") { model.session?.restart() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.session == nil)
                Button("Hint") { model.session?.requestHint() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                    .disabled(model.session?.isHumanTurn != true)
            }
        }
        #if os(macOS) || os(visionOS)
        .defaultSize(width: 980, height: 760)
        .windowResizability(.contentMinSize)
        #endif

        #if os(macOS)
        Settings {
            NavigationStack { SettingsScreen() }
                .environment(model)
                .frame(minWidth: 460, minHeight: 520)
        }
        #endif

        #if os(visionOS)
        ImmersiveSpace(id: BridgyApp.tableSpace) {
            ImmersiveBoardView(
                configuration: model.configuration,
                theme: model.settings.theme,
                style: model.settings.boardStyle,
                agentEngine: model.agentEngine
            )
            .environment(model)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        #endif
    }

    #if os(visionOS)
    /// The board-on-a-table space, opened from the Play tab.
    static let tableSpace = "bridgy.table"
    #endif
}
