import BridgyEngine
import BridgyTraining
import Foundation
import Observation

/// Drives a training run and keeps what the screen plots.
///
/// The agent is written to disk at every checkpoint — each time a new network
/// beats the old one — so stopping, or the app being closed, loses at most one
/// round, never the agent.
@MainActor
@Observable
final class TrainingRun {

    struct LossPoint: Identifiable, Hashable {
        let id: Int
        let step: Int
        let kind: String
        let value: Double
    }

    struct ScorePoint: Identifiable, Hashable {
        var id: String { "\(series)-\(round)" }
        let round: Int
        let series: String
        let score: Double
    }

    struct GatePoint: Identifiable, Hashable {
        var id: Int { round }
        let round: Int
        let score: Double
        let accepted: Bool
    }

    var parameters = TrainingParameters()
    var name = ""

    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var round = 0
    private(set) var roundsPlanned = 0
    private(set) var status = ""
    private(set) var losses: [LossPoint] = []
    private(set) var benchmarks: [ScorePoint] = []
    private(set) var gates: [GatePoint] = []
    private(set) var error: String?
    /// The agent this run is writing to, once its first network has been kept.
    private(set) var agent: SavedAgent?

    private var task: Task<Void, Never>?
    private var control = TrainingControl()
    /// The Live Activity; dismissing it, or its Stop button, stops training.
    @ObservationIgnored private lazy var live = RunActivityController(kind: .training) { [weak self] in
        self?.stop()
    }
    /// Latest benchmark against Hard, for the Live Activity's detail line.
    private var lastHard: Double?
    /// Steps are averaged in groups so a long run plots a few hundred points,
    /// not tens of thousands.
    private var pending: (policy: Double, value: Double, count: Int) = (0, 0, 0)
    private var stepOffset = 0
    private var roundOffset = 0

    /// Starts a new agent, or continues training `existing` from its saved network.
    func start(store: AgentStore, continuing existing: SavedAgent? = nil) {
        stop()
        losses = []
        benchmarks = []
        gates = []
        error = nil
        pending = (0, 0, 0)

        var start: NetworkWeights?
        if let existing {
            do {
                start = try store.weights(for: existing)
            } catch {
                self.error = "Couldn’t load \(existing.name): \(error.localizedDescription)"
                return
            }
            // Board size and network shape belong to the agent; the rest is
            // whatever is set now.
            parameters.boardSize = existing.parameters.boardSize
            parameters.channels = existing.parameters.channels
            parameters.blocks = existing.parameters.blocks
            name = existing.name
        }
        // A new agent never takes an existing one's name, so the one just
        // trained is not quietly shadowed by the next.
        let taken = existing == nil && store.agents.contains { $0.name == name }
        if taken || name.trimmingCharacters(in: .whitespaces).isEmpty { name = store.freshName() }

        agent = existing
        stepOffset = existing?.steps ?? 0
        roundOffset = existing?.rounds ?? 0
        roundsPlanned = parameters.rounds
        round = 0
        isRunning = true
        isPaused = false
        status = "Starting…"
        control = TrainingControl()

        let parameters = parameters
        let control = control
        let seed = UInt64.random(in: 1...UInt64.max)
        lastHard = nil
        live.start(title: "Training \(name)", headline: "Starting…")
        task = Task { [weak self] in
            for await event in Training.run(parameters: parameters, from: start, seed: seed, control: control) {
                guard let self else { return }
                self.handle(event, store: store)
            }
            guard let self, !Task.isCancelled else { return }
            self.isRunning = false
            self.isPaused = false
            if self.error == nil {
                self.status = self.agent == nil
                    ? "Finished, but no network beat the one it started with."
                    : "Finished. \(self.agent?.name ?? "The agent") is saved and can enter the tournament."
            }
            self.live.end(finalHeadline: self.status, detail: self.liveDetail)
        }
    }

    func togglePause() {
        isPaused.toggle()
        let paused = isPaused
        let control = control
        Task { await control.setPaused(paused) }
        if paused { status = "Paused" }
    }

    func stop() {
        task?.cancel()
        task = nil
        if isRunning {
            status = agent == nil ? "Stopped." : "Stopped. The best network so far is saved."
            live.end(finalHeadline: nil)
        }
        isRunning = false
        isPaused = false
    }

    private var liveDetail: String {
        lastHard.map { "vs Hard \(Int(($0 * 100).rounded()))%" } ?? ""
    }

    private func handle(_ event: TrainingEvent, store: AgentStore) {
        defer {
            let done = Double(max(round - 1, 0)) / Double(max(roundsPlanned, 1))
            live.update(progress: done, headline: status, detail: liveDetail)
        }
        switch event {
        case .selfPlay(let round, let finished, let total):
            self.round = round
            if !isPaused { status = "Round \(round): self-play, game \(finished) of \(total)" }

        case .loss(let step, let policy, let value):
            if !isPaused { status = "Round \(round): learning on the GPU" }
            pending.policy += Double(policy)
            pending.value += Double(value)
            pending.count += 1
            let group = max(1, parameters.stepsPerRound / 20)
            if pending.count >= group {
                let x = stepOffset + step
                losses.append(LossPoint(id: x * 2, step: x, kind: "Moves", value: pending.policy / Double(pending.count)))
                losses.append(LossPoint(id: x * 2 + 1, step: x, kind: "Result", value: pending.value / Double(pending.count)))
                pending = (0, 0, 0)
            }

        case .gate(let round, let score, let accepted):
            gates.append(GatePoint(round: roundOffset + round, score: score, accepted: accepted))
            if !isPaused { status = "Round \(round): checking against the best so far" }

        case .benchmark(let round, let opponent, let score):
            benchmarks.append(ScorePoint(round: roundOffset + round, series: opponent, score: score))
            if opponent == Difficulty.hard.displayName { lastHard = score }
            // These always measure the best network so far, which is the one saved.
            if var agent {
                agent.benchmarks[opponent] = score
                self.agent = agent
                store.update(agent)
            }

        case .checkpoint(let round, let steps, let weights):
            let now = Date()
            var saved = agent ?? SavedAgent(
                id: UUID(), name: name, parameters: parameters,
                rounds: 0, steps: 0, created: now, updated: now, benchmarks: [:]
            )
            saved.name = name
            saved.parameters = parameters
            saved.rounds = roundOffset + round
            saved.steps = stepOffset + steps
            saved.updated = now
            do {
                try store.save(saved, weights: weights)
                agent = saved
            } catch {
                self.error = "Couldn’t save: \(error.localizedDescription)"
            }

        case .failed(let message):
            error = message
            status = "Training stopped."
        }
    }
}
