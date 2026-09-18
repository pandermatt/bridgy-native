import BridgyEngine
import SwiftUI

/// Every experiment, newest first, and the way to start another.
struct LabScreen: View {
    @Environment(AppModel.self) private var model
    @State private var path: [UUID] = []
    @State private var drafting: Experiment.Kind?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var library: ExperimentLibrary { model.library }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if showsAgentsLink {
                    Section {
                        NavigationLink {
                            TrainingScreen(run: model.training)
                        } label: {
                            Label("Agents", systemImage: "brain.head.profile")
                        }
                    }
                }
                if library.experiments.isEmpty {
                    starters
                } else {
                    Section("Experiments") {
                        ForEach(library.experiments) { experiment in
                            NavigationLink(value: experiment.id) { row(experiment) }
                                .contextMenu {
                                    Button(role: .destructive) { delete(experiment) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        .onDelete { offsets in
                            for index in offsets { delete(library.experiments[index]) }
                        }
                    }
                    starters
                }
            }
            .navigationTitle("Lab")
            .navigationDestination(for: UUID.self) { id in
                ExperimentDetail(id: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(Experiment.Kind.allCases) { kind in
                            Button { drafting = kind } label: { Label(kind.title, systemImage: kind.symbol) }
                        }
                    } label: {
                        Label("New Experiment", systemImage: "plus")
                    }
                }
            }
            .onChange(of: model.openExperiment, initial: true) { _, id in
                guard let id else { return }
                path = [id]
                model.openExperiment = nil
            }
            .sheet(item: $drafting) { kind in
                NewExperimentSheet(kind: kind) { experiment in
                    library.save(experiment)
                    model.runner.start(experiment, library: library, agents: model.agents)
                    path = [experiment.id]
                }
            }
        }
    }

    /// On iPhone the Lab is also where the agents live; elsewhere the sidebar has them.
    private var showsAgentsLink: Bool {
        #if os(iOS)
        sizeClass != .regular
        #else
        false
        #endif
    }

    private func row(_ experiment: Experiment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: experiment.kind.symbol)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(experiment.name).font(.headline)
                Text(experiment.question).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(statusLine(experiment)).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusLine(_ experiment: Experiment) -> String {
        let played = model.runner.isRunning(experiment.id) ? model.runner.records.count : experiment.gamesPlayed
        let when = experiment.created.formatted(date: .abbreviated, time: .shortened)
        switch experiment.status {
        case .running where model.runner.isRunning(experiment.id): return "Running · \(played) games"
        case .finished: return "\(played) games · \(when)"
        default: return "Stopped at \(played) games · \(when)"
        }
    }

    private func delete(_ experiment: Experiment) {
        if model.runner.isRunning(experiment.id) { model.runner.stop(library: library) }
        library.delete(experiment.id)
    }

    /// Ready-made questions, one tap from an answer.
    private var starters: some View {
        Section {
            ForEach(Experiment.Kind.allCases) { kind in
                Button { drafting = kind } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).foregroundStyle(.primary)
                            Text(kind.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: kind.symbol)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("New experiment")
        } footer: {
            Text("Every game is kept, seeded and replayable, so any result here can be checked — or reproduced from its seed.")
        }
    }
}

/// Sets up one experiment of a given kind.
struct NewExperimentSheet: View {
    let kind: Experiment.Kind
    let onCreate: (Experiment) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var levels: Set<Difficulty> = Set(Difficulty.allCases)
    @State private var agentIDs: Set<UUID> = []
    @State private var smallest = 4
    @State private var largest = 6
    @State private var games = 5
    // Hypothesis
    @State private var subject: String = Difficulty.expert.rawValue
    @State private var opponent: String = Difficulty.hard.rawValue
    @State private var size = 6
    @State private var subjectPlays: Player?
    @State private var p0 = 0.5
    @State private var margin = 0.1
    @State private var errorRate = 0.05

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text(kind.title))
                } footer: {
                    Text(kind.summary)
                }
                if kind == .hypothesis { hypothesisSections } else { fieldSections }
            }
            .formStyle(.grouped)
            .navigationTitle("New \(kind.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Run") { create() }.disabled(!isValid)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
        .onAppear {
            if kind == .mirror { smallest = 4; largest = 12; games = 40 }
        }
    }

    // MARK: - Round robin and mirror

    @ViewBuilder
    private var fieldSections: some View {
        Section("Who plays") {
            ForEach(Difficulty.allCases) { level in
                Toggle(isOn: member(level)) { Label(level.displayName, systemImage: level.symbolName) }
            }
            ForEach(model.agents.agents) { agent in
                Toggle(isOn: member(agent)) {
                    Label {
                        VStack(alignment: .leading) {
                            Text(agent.name)
                            Text(agent.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "brain") }
                }
            }
        }
        Section {
            Stepper("Smallest board: \(smallest)", value: $smallest, in: Board.minimumSize...16)
            Stepper("Largest board: \(max(largest, smallest))", value: $largest, in: smallest...16)
            Stepper(kind == .mirror ? "Games per engine per size: \(games)" : "Games per colour: \(games)",
                    value: $games, in: 1...500)
            LabeledContent("Games in total") { Text("\(draft.scheduledGames)").monospacedDigit() }
        } header: {
            Text("Schedule")
        } footer: {
            let interval = Statistics.wilsonInterval(wins: games / 2, total: max(games, 1))
            Text("With \(games) games a cell, a 50% result is only known to within about ±\(Int((interval.width * 50).rounded())) points. Expert and agents make large boards slow.")
        }
    }

    // MARK: - Hypothesis

    private var choices: [(id: String, name: String)] {
        Difficulty.allCases.map { ($0.rawValue, $0.displayName) }
            + model.agents.agents.map { ($0.id.uuidString, $0.name) }
    }

    @ViewBuilder
    private var hypothesisSections: some View {
        Section {
            Picker("Does", selection: $subject) {
                ForEach(choices, id: \.id) { Text($0.name).tag($0.id) }
            }
            Picker("playing", selection: $subjectPlays) {
                Text("either colour").tag(Player?.none)
                Text("Down (first)").tag(Player?.some(.blue))
                Text("Across (second)").tag(Player?.some(.red))
            }
            Picker("beat", selection: $opponent) {
                ForEach(choices, id: \.id) { Text($0.name).tag($0.id) }
            }
            Stepper("on \(size)×\(size)", value: $size, in: Board.minimumSize...16)
            Picker("more than", selection: $p0) {
                ForEach([0.3, 0.4, 0.5, 0.6, 0.7], id: \.self) { Text($0, format: .percent).tag($0) }
            }
        } header: {
            Text("Claim")
        } footer: {
            Text(draft.question)
        }
        Section {
            Picker("Smallest difference worth finding", selection: $margin) {
                ForEach([0.05, 0.1, 0.15, 0.2], id: \.self) { Text("\(Int($0 * 100)) points").tag($0) }
            }
            Picker("Error rates", selection: $errorRate) {
                Text("10%").tag(0.1)
                Text("5%").tag(0.05)
                Text("1%").tag(0.01)
            }
        } header: {
            Text("Test")
        } footer: {
            Text("A sequential probability ratio test: games are played until the evidence either supports the claim (at least \(Int((p0 + margin) * 100))%) or rejects it (at most \(Int(p0 * 100))%), each with at most \(Int(errorRate * 100))% chance of being wrong. It stops at 2,000 games if still undecided.")
        }
    }

    // MARK: - Building

    private func member(_ level: Difficulty) -> Binding<Bool> {
        Binding(get: { levels.contains(level) },
                set: { if $0 { levels.insert(level) } else { levels.remove(level) } })
    }

    private func member(_ agent: SavedAgent) -> Binding<Bool> {
        Binding(get: { agentIDs.contains(agent.id) },
                set: { if $0 { agentIDs.insert(agent.id) } else { agentIDs.remove(agent.id) } })
    }

    private func entrant(_ id: String) -> Experiment.Entrant? {
        if let level = Difficulty(rawValue: id) { return ExperimentRunner.entrant(for: level) }
        guard let agent = model.agents.agents.first(where: { $0.id.uuidString == id }) else { return nil }
        return ExperimentRunner.entrant(for: agent, agents: model.agents)
    }

    private var draft: Experiment {
        var entrants: [Experiment.Entrant]
        var hypothesis: Experiment.Hypothesis?
        var sizes = Array(smallest...max(largest, smallest))
        if kind == .hypothesis {
            entrants = [entrant(subject), entrant(opponent)].compactMap { $0 }
            sizes = [size]
            hypothesis = Experiment.Hypothesis(
                subject: 0, opponent: 1, size: size, subjectPlays: subjectPlays,
                p0: p0, p1: min(0.99, p0 + margin), alpha: errorRate, beta: errorRate
            )
        } else {
            entrants = Difficulty.allCases.filter(levels.contains).map(ExperimentRunner.entrant(for:))
            entrants += model.agents.agents.filter { agentIDs.contains($0.id) }
                .map { ExperimentRunner.entrant(for: $0, agents: model.agents) }
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return Experiment(
            id: UUID(), name: trimmed.isEmpty ? kind.title : trimmed, kind: kind, created: .now,
            entrants: entrants, sizes: sizes, gamesPerUnit: games, hypothesis: hypothesis,
            seed: UInt64.random(in: 1...UInt64.max), appVersion: Experiment.currentAppVersion
        )
    }

    private var isValid: Bool {
        switch kind {
        case .roundRobin: levels.count + agentIDs.count >= 2
        case .mirror: levels.count + agentIDs.count >= 1
        case .hypothesis: subject != opponent || subjectPlays != nil
        }
    }

    private func create() {
        onCreate(draft)
        dismiss()
    }
}
