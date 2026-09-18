import BridgyEngine
import BridgyTraining
import Charts
import SwiftUI

/// Train an agent by self-play on the GPU, and watch it get better.
struct TrainingScreen: View {
    @Environment(AppModel.self) private var model
    @Bindable var run: TrainingRun
    @State private var renaming: SavedAgent?
    @State private var newName = ""
    @State private var importing = false
    @State private var importError: String?

    private var p: Binding<TrainingParameters> { $run.parameters }

    var body: some View {
        Form {
            // What you have first, then what you can make.
            agentsSection
            controlSection
            if !run.benchmarks.isEmpty || !run.gates.isEmpty { strengthSection }
            if !run.losses.isEmpty { lossSection }
            // While it trains there is nothing to set: the settings are fixed
            // for the run, and a screen of dead controls only gets in the way.
            if !run.isRunning { setupSections }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { importing = true } label: {
                    Label("Import Agent…", systemImage: "square.and.arrow.down")
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.bridgyAgent], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            do {
                for url in urls { try model.agents.importAgent(from: url) }
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
        }
        .navigationTitle("Agents")
        .alert("Rename Agent", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming { model.agents.rename(renaming, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    // MARK: - Running

    private var controlSection: some View {
        Section {
            if run.isRunning {
                LabeledContent(run.name) {
                    Text("\(run.parameters.boardSize)×\(run.parameters.boardSize) · \(run.parameters.channels)×\(run.parameters.blocks) · \(run.parameters.simulations) sims")
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(max(run.round - 1, 0)), total: Double(max(run.roundsPlanned, 1)))
                    Text(run.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Button { run.togglePause() } label: {
                        Label(run.isPaused ? "Resume" : "Pause", systemImage: run.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) { run.stop() } label: {
                        Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            } else {
                if !run.status.isEmpty {
                    Text(run.status).font(.footnote).foregroundStyle(.secondary)
                }
                Button { run.start(store: model.agents) } label: {
                    Text("Train \(run.parameters.rounds) Rounds").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(GraphTrainer.unavailableReason != nil)
                if let reason = GraphTrainer.unavailableReason?.errorDescription {
                    Label(reason, systemImage: "cpu").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let error = run.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Train a new agent")
        } footer: {
            Text("Each round the best network so far plays itself, learns from those games on the GPU, and the result has to beat it to take its place. Training runs while this app is open.")
        }
    }

    private var strengthSection: some View {
        Section {
            Chart {
                ForEach(run.benchmarks) { point in
                    LineMark(x: .value("Round", point.round), y: .value("Win rate", point.score))
                        .foregroundStyle(by: .value("Against", point.series))
                        .interpolationMethod(.monotone)
                }
                ForEach(run.gates) { gate in
                    PointMark(x: .value("Round", gate.round), y: .value("Win rate", gate.score))
                        .symbol(gate.accepted ? .circle : .cross)
                        .foregroundStyle(by: .value("Against", "Previous best"))
                }
                RuleMark(y: .value("Even", 0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(format: Decimal.FormatStyle.Percent.percent.precision(.fractionLength(0)))
            }
            .chartXAxisLabel("Round")
            .frame(height: 220)
            .padding(.vertical, 4)
        } header: {
            Text("Strength")
        } footer: {
            Text("Lines: the best network so far against three of the built-in levels, in both colours. Dots: each new network against the best — a circle means it won enough to replace it, a cross means it did not.")
        }
    }

    private var lossSection: some View {
        Section {
            Chart(run.losses) { point in
                LineMark(x: .value("Step", point.step), y: .value("Loss", point.value))
                    .foregroundStyle(by: .value("Predicting", point.kind))
            }
            .chartXAxisLabel("Training step")
            .frame(height: 180)
            .padding(.vertical, 4)
        } header: {
            Text("Loss")
        } footer: {
            Text("How far the network's guesses are from what the search found (moves) and from how games ended (result). These fall slowly and jump when new games arrive; the strength chart is the one that matters.")
        }
    }

    // MARK: - Setup

    @ViewBuilder
    private var setupSections: some View {
        Section {
            TextField("Name", text: $run.name, prompt: Text(model.agents.freshName()))
            Stepper("Board: \(run.parameters.boardSize)×\(run.parameters.boardSize)",
                    value: p.boardSize, in: 3...9)
        } header: {
            Text("Agent")
        } footer: {
            Text("It practises on one size and plays every size, best the one it practised on. Each size up makes games longer and training slower.")
        }

        Section {
            Picker("Width", selection: p.channels) {
                ForEach([16, 32, 64], id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            Stepper("Depth: \(run.parameters.blocks) blocks", value: p.blocks, in: 1...8)
            LabeledContent("Parameters") {
                Text(run.parameters.architecture.parameterCount, format: .number).monospacedDigit()
            }
        } header: {
            Text("Network")
        } footer: {
            Text("Wider sees more patterns; deeper sees further across the board. Both make every move slower to think about.")
        }

        Section {
            Stepper("Search: \(run.parameters.simulations) per move", value: p.simulations, in: 8...400, step: 8)
            Stepper("Games per round: \(run.parameters.gamesPerRound)", value: p.gamesPerRound, in: 8...256, step: 8)
            Stepper("Rounds: \(run.parameters.rounds)", value: p.rounds, in: 1...500)
        } header: {
            Text("Self-play")
        } footer: {
            Text("More search per move makes better games to learn from, and a stronger player in the tournament, at the cost of time.")
        }

        Section {
            Picker("Learning rate", selection: p.learningRate) {
                ForEach([0.0005, 0.001, 0.002, 0.005], id: \.self) { Text($0, format: .number).tag($0) }
            }
            Picker("Batch size", selection: p.batchSize) {
                ForEach([32, 64, 128, 256], id: \.self) { Text("\($0)").tag($0) }
            }
            Stepper("Steps per round: \(run.parameters.stepsPerRound)", value: p.stepsPerRound, in: 50...2_000, step: 50)
        } header: {
            Text("Learning")
        }

        Section {
            Stepper("Games: \(run.parameters.gateGames)", value: p.gateGames, in: 8...100, step: 4)
            Picker("Must win", selection: p.gateThreshold) {
                ForEach([0.5, 0.55, 0.6], id: \.self) { Text($0, format: .percent).tag($0) }
            }
        } header: {
            Text("Gate")
        } footer: {
            Text("A new network only replaces the best if it wins this share of games against it, half as each colour. Once both win every game they play first, neither can reach more than half — that is the game, not a fault.")
        }
    }

    // MARK: - Agents

    private var agentsSection: some View {
        Section {
            if model.agents.agents.isEmpty {
                Text("None yet. A trained agent is saved as soon as it beats its starting point.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.agents.agents) { agent in
                NavigationLink {
                    AgentDetailView(agentID: agent.id, run: run)
                } label: {
                    Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(agent.name).font(.headline)
                        Text(agent.summary).font(.footnote).foregroundStyle(.secondary)
                        if !agent.benchmarks.isEmpty {
                            Text(benchmarkLine(agent)).font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    } icon: {
                        Image(systemName: agent.symbolName).foregroundStyle(.tint)
                    }
                }
                .contextMenu { actions(for: agent) }
                .swipeActions { actions(for: agent) }
            }
            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Saved agents")
        } footer: {
            Text("Open an agent to play it, share it, export it to Files or train it further. Agents shared with you come in with Import, or by opening the .bridgyagent file.")
        }
    }

    @ViewBuilder
    private func actions(for agent: SavedAgent) -> some View {
        Button(role: .destructive) { model.agents.delete(agent) } label: {
            Label("Delete", systemImage: "trash")
        }
        .disabled(run.isRunning && run.agent?.id == agent.id)
        Button {
            newName = agent.name
            renaming = agent
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button { run.start(store: model.agents, continuing: agent) } label: {
            Label("Continue Training", systemImage: "arrow.clockwise")
        }
        .disabled(run.isRunning || GraphTrainer.unavailableReason != nil)
    }

    private func benchmarkLine(_ agent: SavedAgent) -> String {
        ["Easy", "Medium", "Hard"].compactMap { name in
            agent.benchmarks[name].map { "\(name) \(Int(($0 * 100).rounded()))%" }
        }
        .joined(separator: " · ")
    }
}
