import BridgyEngine
import Foundation
import Observation

/// Plays one experiment at a time and keeps its games as they arrive.
///
/// Lives on the app model, so an experiment keeps running — and its results
/// stay on screen — while you play a game or look at something else.
@MainActor
@Observable
final class ExperimentRunner {
    private(set) var runningID: UUID?
    /// The running experiment's games so far, published a few times a second.
    private(set) var records: [GameRecord] = []
    /// The running hypothesis test, if that is what is running.
    private(set) var sequential: SequentialTest?
    private(set) var error: String?

    private var task: Task<Void, Never>?
    private static let publishInterval = Duration.milliseconds(150)

    var isRunning: Bool { runningID != nil }

    func isRunning(_ id: UUID) -> Bool { runningID == id }

    /// The games of `id`, live if it is the one running.
    func games(for id: UUID, library: ExperimentLibrary) -> [GameRecord] {
        runningID == id ? records : library.games(for: id)
    }

    func start(_ original: Experiment, library: ExperimentLibrary, agents: AgentStore) {
        stop(library: library)
        error = nil
        let participants: [Participant]
        do {
            participants = try Self.participants(for: original.entrants, agents: agents)
        } catch {
            self.error = error.localizedDescription
            return
        }

        var experiment = original
        experiment.status = .running
        experiment.gamesPlayed = 0
        experiment.appVersion = Experiment.currentAppVersion
        library.save(experiment, games: [])

        let jobs = Self.jobs(for: experiment)
        let hypothesis = experiment.hypothesis
        runningID = experiment.id
        records = []
        sequential = hypothesis.map { SequentialTest(p0: $0.p0, p1: $0.p1, alpha: $0.alpha, beta: $0.beta) }

        task = Task { [weak self] in
            let clock = ContinuousClock()
            var lastPublish = clock.now
            var working: [GameRecord] = []
            var test = hypothesis.map { SequentialTest(p0: $0.p0, p1: $0.p1, alpha: $0.alpha, beta: $0.beta) }
            for await outcome in Tournament.stream(jobs: jobs, participants: participants) {
                let record = GameRecord(outcome)
                working.append(record)
                if let h = hypothesis {
                    test?.record(win: outcome.winnerIndex == h.subject)
                }
                if clock.now - lastPublish >= Self.publishInterval {
                    lastPublish = clock.now
                    self?.records = working
                    self?.sequential = test
                }
                // Decided: stop here. Breaking out ends the stream, which
                // cancels the games still in flight.
                if let test, test.decision != .undecided { break }
            }
            guard let self, self.runningID == experiment.id else { return }
            var done = experiment
            done.status = Task.isCancelled ? .stopped : .finished
            done.gamesPlayed = working.count
            self.records = working
            self.sequential = test
            library.save(done, games: working)
            self.runningID = nil
        }
    }

    /// Stops the run and keeps every game played so far.
    func stop(library: ExperimentLibrary) {
        guard let id = runningID, var experiment = library.experiment(id) else { return }
        task?.cancel()
        task = nil
        experiment.status = .stopped
        experiment.gamesPlayed = records.count
        library.save(experiment, games: records)
        runningID = nil
    }

    // MARK: - Building a run

    enum Failure: LocalizedError {
        case missingAgent(String)
        var errorDescription: String? {
            switch self {
            case .missingAgent(let name): "\(name) is no longer among your agents."
            }
        }
    }

    static func participants(for entrants: [Experiment.Entrant], agents: AgentStore) throws -> [Participant] {
        try entrants.map { entrant in
            if let level = entrant.level {
                return Participant(name: entrant.name) { level.tournamentEngine(forSize: $0) }
            }
            guard let id = entrant.agentID,
                  let agent = agents.agents.first(where: { $0.id == id }),
                  let network = agents.network(for: agent) else {
                throw Failure.missingAgent(entrant.name)
            }
            let engine = NeuralMCTSEngine(network: network, simulations: agent.parameters.simulations, name: agent.name)
            return Participant(name: entrant.name, engine: engine)
        }
    }

    static func jobs(for experiment: Experiment) -> [Tournament.Job] {
        switch experiment.kind {
        case .roundRobin:
            let configuration = TournamentConfiguration(
                minimumSize: experiment.sizes.min() ?? 4,
                maximumSize: experiment.sizes.max() ?? 4,
                gamesPerColour: experiment.gamesPerUnit
            )
            return Tournament.jobs(configuration: configuration, participants: experiment.entrants.count, seed: experiment.seed)
        case .mirror:
            return Tournament.mirrorJobs(
                sizes: experiment.sizes, participants: experiment.entrants.count,
                gamesPerSize: experiment.gamesPerUnit, seed: experiment.seed
            )
        case .hypothesis:
            guard let h = experiment.hypothesis else { return [] }
            return Tournament.matchJobs(
                first: h.subject, second: h.opponent, size: h.size,
                firstPlays: h.subjectPlays, games: h.maxGames, seed: experiment.seed
            )
        }
    }

    /// An entrant for a saved agent, pinned to the network it has right now.
    static func entrant(for agent: SavedAgent, agents: AgentStore) -> Experiment.Entrant {
        let hash = (try? agents.weights(for: agent)).map(Experiment.hash(of:))
        return Experiment.Entrant(name: agent.name, agentID: agent.id, weightsHash: hash)
    }

    static func entrant(for level: Difficulty) -> Experiment.Entrant {
        Experiment.Entrant(name: level.displayName, level: level)
    }
}
