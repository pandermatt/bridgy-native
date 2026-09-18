import AppIntents
import BridgyEngine
import BridgyTraining
import CoreTransferable
import Foundation

// MARK: - Entities

/// An experiment, as Siri and Shortcuts see it.
///
/// The Lab marks the experiment on screen with this entity, and its
/// `Transferable` representation is the full report — so asking Siri about
/// "this" hands it the question, the findings and the numbers behind them.
struct ExperimentEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Experiment"
    static let defaultQuery = ExperimentQuery()

    let id: UUID
    let name: String
    let question: String
    let report: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(question)")
    }

    @MainActor
    init(_ experiment: Experiment, library: ExperimentLibrary) {
        id = experiment.id
        name = experiment.name
        question = experiment.question
        let analysis = ExperimentAnalysis(experiment: experiment, games: library.games(for: experiment.id))
        report = ReportWriter.markdown(analysis)
    }
}

extension ExperimentEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.report)
    }
}

struct ExperimentQuery: EntityQuery {
    @Dependency var model: AppModel

    func entities(for identifiers: [UUID]) async throws -> [ExperimentEntity] {
        await MainActor.run {
            identifiers.compactMap { model.library.experiment($0) }
                .map { ExperimentEntity($0, library: model.library) }
        }
    }

    func suggestedEntities() async throws -> [ExperimentEntity] {
        await MainActor.run {
            model.library.experiments.prefix(10).map { ExperimentEntity($0, library: model.library) }
        }
    }
}

/// A trained agent.
struct AgentEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Agent"
    static let defaultQuery = AgentQuery()

    let id: UUID
    let name: String
    let summary: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
    }
}

struct AgentQuery: EntityQuery {
    @Dependency var model: AppModel

    func entities(for identifiers: [UUID]) async throws -> [AgentEntity] {
        await MainActor.run {
            model.agents.agents.filter { identifiers.contains($0.id) }
                .map { AgentEntity(id: $0.id, name: $0.name, summary: $0.summary) }
        }
    }

    func suggestedEntities() async throws -> [AgentEntity] {
        await MainActor.run {
            model.agents.agents.map { AgentEntity(id: $0.id, name: $0.name, summary: $0.summary) }
        }
    }
}

/// The game on screen, so "this game" means something to Siri.
struct GameEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Game"
    static let defaultQuery = GameQuery()

    let id: UUID
    let summary: String
    let status: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(summary)", subtitle: "\(status)")
    }

    @MainActor
    init(_ session: GameSession) {
        id = session.id
        summary = session.configuration.summary
        var lines = [session.statusText, "\(session.state.moveCount) moves played."]
        if let down = session.readout.blue { lines.append("\(Player.blue.displayName) needs \(down) more.") }
        if let across = session.readout.red { lines.append("\(Player.red.displayName) needs \(across) more.") }
        status = lines.joined(separator: " ")
    }
}

extension GameEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { "Bridgy game, \($0.summary). \($0.status)" }
    }
}

struct GameQuery: EntityQuery {
    @Dependency var model: AppModel

    func entities(for identifiers: [UUID]) async throws -> [GameEntity] {
        await MainActor.run {
            guard let session = model.session, identifiers.contains(session.id) else { return [] }
            return [GameEntity(session)]
        }
    }

    func suggestedEntities() async throws -> [GameEntity] {
        await MainActor.run { model.session.map { [GameEntity($0)] } ?? [] }
    }
}

enum OpponentOption: String, AppEnum {
    case easy, casual, medium, hard, expert, perfect

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Opponent"
    static let caseDisplayRepresentations: [OpponentOption: DisplayRepresentation] = [
        .easy: "Easy", .casual: "Casual", .medium: "Medium",
        .hard: "Hard", .expert: "Expert", .perfect: "Perfect"
    ]

    var difficulty: Difficulty { Difficulty(rawValue: rawValue) ?? .medium }
}

enum ExperimentKindOption: String, AppEnum {
    case roundRobin, mirror

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Experiment"
    static let caseDisplayRepresentations: [ExperimentKindOption: DisplayRepresentation] = [
        .roundRobin: "Round Robin", .mirror: "Mirror Matches"
    ]
}

// MARK: - Intents

struct StartGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Game"
    static let description = IntentDescription("Starts a game of Bridgy against a computer opponent. You play Down and move first.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Opponent", default: .medium) var opponent: OpponentOption
    @Parameter(title: "Board size", default: 6, inclusiveRange: (3, 12)) var size: Int

    @Dependency var model: AppModel

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$opponent) on a \(\.$size) board")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        var configuration = GameConfiguration.default
        configuration.size = size
        configuration.blue = .human
        configuration.red = .computer(opponent.difficulty)
        model.startGame(configuration)
        model.requestedTab = .play
        return .result()
    }
}

/// "What move should I play?" — highlights the suggestion on the board and
/// says it aloud. The same suggestion as the Hint button.
struct SuggestMoveIntent: AppIntent {
    static let title: LocalizedStringResource = "Suggest a Move"
    static let description = IntentDescription("Shows the recommended move on the board in the game you're playing, and says where it is.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Dependency var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let session = model.session else {
            return .result(dialog: "There's no game in progress. Start one in Bridgy first.")
        }
        model.requestedTab = .play
        if session.state.isOver {
            return .result(dialog: "This game is over. Start a new one and ask again.")
        }
        guard session.isHumanTurn else {
            return .result(dialog: "It's not your turn yet — wait for \(session.currentSeat.displayName) to move.")
        }
        guard let move = await session.suggestMove() else {
            return .result(dialog: "I couldn't find a move to suggest.")
        }
        let text = "Play \(session.describe(move)). \(session.reason(for: move)) It's highlighted on the board."
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct RunExperimentIntent: AppIntent {
    static let title: LocalizedStringResource = "Run an Experiment"
    static let description = IntentDescription("Runs a round robin or mirror matches with every built-in engine and opens it in the Lab.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Kind", default: .mirror) var kind: ExperimentKindOption
    @Parameter(title: "Smallest board", default: 4, inclusiveRange: (2, 16)) var smallest: Int
    @Parameter(title: "Largest board", default: 8, inclusiveRange: (2, 16)) var largest: Int

    @Dependency var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<ExperimentEntity> {
        let kind: Experiment.Kind = self.kind == .mirror ? .mirror : .roundRobin
        let experiment = Experiment(
            id: UUID(), name: kind.title, kind: kind, created: .now,
            entrants: Difficulty.allCases.map(ExperimentRunner.entrant(for:)),
            sizes: Array(min(smallest, largest)...max(smallest, largest)),
            gamesPerUnit: kind == .mirror ? 40 : 5, hypothesis: nil,
            seed: UInt64.random(in: 1...UInt64.max), appVersion: Experiment.currentAppVersion
        )
        model.library.save(experiment)
        model.runner.start(experiment, library: model.library, agents: model.agents)
        model.requestedTab = .lab
        model.openExperiment = experiment.id
        return .result(value: ExperimentEntity(experiment, library: model.library))
    }
}

struct SummarizeExperimentIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize an Experiment"
    static let description = IntentDescription("Reads out what an experiment found, writing the findings first if needed.")

    @Parameter(title: "Experiment") var experiment: ExperimentEntity?

    @Dependency var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let id = experiment?.id ?? model.library.experiments.first?.id,
              var stored = model.library.experiment(id) else {
            return .result(value: "", dialog: "There are no experiments in the Lab yet.")
        }
        if stored.findings == nil {
            let analysis = ExperimentAnalysis(experiment: stored, games: model.library.games(for: id))
            let facts = FactSheet.facts(for: analysis)
            let findings = FindingsWriter.availability == .available
                ? ((try? await FindingsWriter.write(facts: facts)) ?? FindingsWriter.template(facts: facts, analysis: analysis))
                : FindingsWriter.template(facts: facts, analysis: analysis)
            stored.findings = findings
            model.library.save(stored)
        }
        guard let findings = stored.findings else { return .result(value: "", dialog: "Nothing to summarise yet.") }
        let text = ([findings.headline] + findings.findings.prefix(2).map(\.statement)).joined(separator: " ")
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct TrainAgentIntent: AppIntent, ProgressReportingIntent {
    static let title: LocalizedStringResource = "Train an Agent"
    static let description = IntentDescription("Trains a new agent by self-play on the GPU with the settings last used in the app.")

    @Parameter(title: "Rounds", default: 20, inclusiveRange: (1, 200)) var rounds: Int

    @Dependency var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let reason = GraphTrainer.unavailableReason {
            return .result(dialog: IntentDialog(stringLiteral: reason.errorDescription ?? "Training isn't available here."))
        }
        progress.totalUnitCount = Int64(rounds)
        let model = self.model, rounds = self.rounds, progress = self.progress
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            // On 27 the system lets this keep the GPU after you leave the app.
            try await performBackgroundTask(options: .requiresGPU) { @Sendable @MainActor in
                await Self.train(model: model, rounds: rounds, progress: progress)
            }
        } else {
            await Self.train(model: model, rounds: rounds, progress: progress)
        }
        let name = model.training.agent?.name ?? "The agent"
        return .result(dialog: IntentDialog(stringLiteral: model.training.agent == nil
            ? "Training finished, but no network beat the one it started from."
            : "\(name) is trained and saved. It can enter the tournament in the Lab."))
    }

    @MainActor
    private static func train(model: AppModel, rounds: Int, progress: Progress) async {
        let run = model.training
        run.parameters.rounds = rounds
        run.name = ""
        run.start(store: model.agents)
        while run.isRunning, !Task.isCancelled {
            progress.completedUnitCount = Int64(max(0, run.round - 1))
            try? await Task.sleep(for: .seconds(1))
        }
        if Task.isCancelled { run.stop() }
        progress.completedUnitCount = Int64(rounds)
    }
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, *)
extension TrainAgentIntent: LongRunningIntent {}

// MARK: - Shortcuts

struct BridgyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartGameIntent(),
            phrases: ["Start a game in \(.applicationName)", "Play \(.applicationName) against \(\.$opponent)"],
            shortTitle: "Start a Game", systemImageName: "play.circle"
        )
        AppShortcut(
            intent: SuggestMoveIntent(),
            phrases: [
                "What move should I play in \(.applicationName)",
                "Recommend a move in \(.applicationName)",
                "Give me a hint in \(.applicationName)",
                "What's my best move in \(.applicationName)"
            ],
            shortTitle: "Suggest a Move", systemImageName: "lightbulb"
        )
        AppShortcut(
            intent: SummarizeExperimentIntent(),
            phrases: ["Summarize my experiment in \(.applicationName)", "What did \(.applicationName) find"],
            shortTitle: "Summarize Experiment", systemImageName: "apple.intelligence"
        )
        AppShortcut(
            intent: RunExperimentIntent(),
            phrases: ["Run an experiment in \(.applicationName)", "Run \(\.$kind) in \(.applicationName)"],
            shortTitle: "Run Experiment", systemImageName: "flask"
        )
        AppShortcut(
            intent: TrainAgentIntent(),
            phrases: ["Train an agent in \(.applicationName)"],
            shortTitle: "Train Agent", systemImageName: "brain.head.profile"
        )
    }
}
