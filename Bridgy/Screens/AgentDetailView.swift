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

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var usesSidebar: Bool { sizeClass == .regular }
    #else
    private var usesSidebar: Bool { true }
    #endif

    private var agent: SavedAgent? { model.agents.agents.first { $0.id == agentID } }

    var body: some View {
        if let agent {
            Form {
                identitySection(agent)
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
                    Button {
                        run.start(store: model.agents, continuing: agent)
                        dismiss()
                        // From the sidebar there is nothing to go back to: go
                        // to Agents, where the run's progress is.
                        if usesSidebar { model.requestedTab = .agents }
                    } label: {
                        Label("Continue Training", systemImage: "arrow.clockwise")
                    }
                    .disabled(run.isRunning || GraphTrainer.unavailableReason != nil)
                }
                Section {
                    if let file = try? model.agents.file(for: agent) {
                        ShareLink(item: SharedAgent(file: file), preview: SharePreview(agent.name, image: Image(systemName: agent.symbolName))) {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button { export(agent) } label: {
                        Label("Export to Files…", systemImage: "folder")
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

    /// Name and symbol, the two things that are the agent's own to choose.
    private func identitySection(_ agent: SavedAgent) -> some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: agent.symbolName)
                    .font(.title)
                    .foregroundStyle(.tint)
                    .frame(width: 52, height: 52)
                    .background(.tint.opacity(0.15), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name).font(.title3.weight(.semibold))
                    Text(agent.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Rename") {
                    newName = agent.name
                    renaming = true
                }
                .buttonStyle(.bordered)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 8)], spacing: 8) {
                ForEach(SavedAgent.symbols, id: \.self) { symbol in
                    Button {
                        model.agents.setSymbol(symbol, for: agent)
                    } label: {
                        Image(systemName: symbol)
                            .font(.title3)
                            .frame(width: 40, height: 40)
                            .background(
                                symbol == agent.symbolName ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                                in: .rect(cornerRadius: 10)
                            )
                            .foregroundStyle(symbol == agent.symbolName ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                    .accessibilityAddTraits(symbol == agent.symbolName ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Name and icon")
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
