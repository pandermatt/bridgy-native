import BridgyEngine
import BridgyTraining
import SwiftUI

/// One saved agent: what it is, how strong it is, and what to do with it.
struct AgentDetailView: View {
    let agentID: UUID
    @Bindable var run: TrainingRun
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var exporting: AgentDocument?
    @State private var confirmingDelete = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var error: String?

    private var agent: SavedAgent? { model.agents.agents.first { $0.id == agentID } }

    var body: some View {
        if let agent {
            Form {
                Section {
                    LabeledContent("Practised on", value: "\(agent.parameters.boardSize)×\(agent.parameters.boardSize)")
                    LabeledContent("Network", value: "\(agent.parameters.channels) wide, \(agent.parameters.blocks) deep")
                    LabeledContent("Search", value: "\(agent.parameters.simulations) positions a move")
                    LabeledContent("Trained", value: "\(agent.rounds) rounds, \(agent.steps) steps")
                    LabeledContent("Updated", value: agent.updated.formatted(date: .abbreviated, time: .shortened))
                }
                if !agent.benchmarks.isEmpty {
                    Section("Last benchmark") {
                        ForEach(agent.benchmarks.sorted { $0.key < $1.key }, id: \.key) { name, score in
                            LabeledContent("Against \(name)") {
                                Text(score, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                            }
                        }
                    }
                }
                Section {
                    Button { play(agent) } label: {
                        Label("Play Against \(agent.name)", systemImage: "play.fill")
                    }
                    Button { run.start(store: model.agents, continuing: agent); dismiss() } label: {
                        Label("Continue Training", systemImage: "arrow.clockwise")
                    }
                    .disabled(run.isRunning || GraphTrainer.unavailableReason != nil)
                }
                Section {
                    if let file = try? model.agents.file(for: agent) {
                        ShareLink(item: SharedAgent(file: file), preview: SharePreview(agent.name, image: Image(systemName: "brain"))) {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button { export(agent) } label: {
                        Label("Export to Files…", systemImage: "folder")
                    }
                    Button {
                        newName = agent.name
                        renaming = true
                    } label: {
                        Label("Rename…", systemImage: "pencil")
                    }
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete Agent", systemImage: "trash")
                    }
                    .disabled(run.isRunning && run.agent?.id == agent.id)
                } footer: {
                    Text("A shared agent is a single .bridgyagent file with its network inside. Anyone with Bridgy can open it to play it, train it on, or enter it in the Lab.")
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(agent.name)
            .fileExporter(
                isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                document: exporting,
                contentType: .bridgyAgent,
                defaultFilename: agent.name
            ) { _ in exporting = nil }
            .confirmationDialog("Delete \(agent.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    model.agents.delete(agent)
                    dismiss()
                }
            } message: {
                Text("Its network is removed from this device. Experiments that used it keep their games.")
            }
            .alert("Rename Agent", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Rename") { model.agents.rename(agent, to: newName) }
                Button("Cancel", role: .cancel) {}
            }
        } else {
            ContentUnavailableView("Agent deleted", systemImage: "brain")
        }
    }

    private func export(_ agent: SavedAgent) {
        do {
            exporting = AgentDocument(data: try model.agents.file(for: agent).encoded())
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func play(_ agent: SavedAgent) {
        model.startGame(GameConfiguration(
            size: agent.parameters.boardSize,
            blue: .human,
            red: .agent(agent.id, name: agent.name)
        ))
        model.requestedTab = .play
    }
}
