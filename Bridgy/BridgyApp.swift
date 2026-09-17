import SwiftUI

@main
struct BridgyApp: App {
    @State private var model = AppModel()

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
            CommandMenu("Game") {
                Button("Restart") { model.session?.restart() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.session == nil)
                Button("Hint") { model.session?.requestHint() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                    .disabled(model.session?.isHumanTurn != true)
            }
        }
        #if os(macOS)
        .defaultSize(width: 980, height: 760)
        #endif
    }
}
