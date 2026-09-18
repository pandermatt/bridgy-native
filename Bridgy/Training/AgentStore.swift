import BridgyEngine
import BridgyTraining
import Foundation
import Observation

/// A trained agent, as listed: everything but its weights.
struct SavedAgent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// What it was trained with. Board size and network shape are fixed once
    /// trained; the rest can change if training is continued.
    var parameters: TrainingParameters
    var rounds: Int
    var steps: Int
    var created: Date
    var updated: Date
    /// Latest win rate against each benchmark opponent, by name.
    var benchmarks: [String: Double]

    var summary: String {
        let size = parameters.boardSize
        return "\(size)×\(size) · \(rounds) rounds · \(parameters.channels)×\(parameters.blocks) network"
    }

    /// The engine it plays as.
    func engine(weights: NetworkWeights) -> NeuralMCTSEngine {
        NeuralMCTSEngine(network: NeuralNetwork(weights: weights), simulations: parameters.simulations, name: name)
    }
}

/// Keeps trained agents in `Application Support/Bridgy/Agents/<id>/`: the
/// description in `agent.json`, the network in `weights.bin`.
@MainActor
@Observable
final class AgentStore {
    private(set) var agents: [SavedAgent] = []
    private let directory: URL
    /// Networks already read from disk, by agent and the save they came from.
    @ObservationIgnored private var networks: [UUID: (updated: Date, network: NeuralNetwork)] = [:]

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.temporaryDirectory
        directory = base.appendingPathComponent("Bridgy/Agents", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    private func folder(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        agents = folders
            .compactMap { try? Data(contentsOf: $0.appendingPathComponent("agent.json")) }
            .compactMap { try? JSONDecoder().decode(SavedAgent.self, from: $0) }
            .sorted { $0.created < $1.created }
    }

    func save(_ agent: SavedAgent, weights: NetworkWeights) throws {
        let folder = folder(agent.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try weights.data().write(to: folder.appendingPathComponent("weights.bin"), options: .atomic)
        try JSONEncoder().encode(agent).write(to: folder.appendingPathComponent("agent.json"), options: .atomic)
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }
    }

    /// Rewrites the description only; the weights are untouched.
    func update(_ agent: SavedAgent) {
        guard let data = try? JSONEncoder().encode(agent) else { return }
        try? data.write(to: folder(agent.id).appendingPathComponent("agent.json"), options: .atomic)
        if let index = agents.firstIndex(where: { $0.id == agent.id }) { agents[index] = agent }
    }

    func weights(for agent: SavedAgent) throws -> NetworkWeights {
        let data = try Data(contentsOf: folder(agent.id).appendingPathComponent("weights.bin"))
        return try NetworkWeights(architecture: agent.parameters.architecture, data: data)
    }

    /// The agent's network, read once and kept.
    func network(for agent: SavedAgent) -> NeuralNetwork? {
        if let cached = networks[agent.id], cached.updated == agent.updated { return cached.network }
        guard let weights = try? weights(for: agent) else { return nil }
        let network = NeuralNetwork(weights: weights)
        networks[agent.id] = (agent.updated, network)
        return network
    }

    /// The agent as a single shareable file.
    func file(for agent: SavedAgent) throws -> AgentFile {
        AgentFile(agent: agent, weights: try weights(for: agent))
    }

    /// Adds an agent from a file. One that is already here comes in as a copy
    /// with its own id, so importing never overwrites anything.
    @discardableResult
    func importAgent(from url: URL) throws -> SavedAgent {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let file = try AgentFile.decode(try Data(contentsOf: url))
        var agent = file.agent
        if agents.contains(where: { $0.id == agent.id }) {
            agent = SavedAgent(
                id: UUID(), name: agent.name + " (copy)", parameters: agent.parameters,
                rounds: agent.rounds, steps: agent.steps, created: agent.created,
                updated: .now, benchmarks: agent.benchmarks
            )
        }
        let weights = try NetworkWeights(architecture: agent.parameters.architecture, data: file.weights)
        try save(agent, weights: weights)
        return agent
    }

    func rename(_ agent: SavedAgent, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var updated = agents.first(where: { $0.id == agent.id }) else { return }
        updated.name = trimmed
        update(updated)
    }

    func delete(_ agent: SavedAgent) {
        try? FileManager.default.removeItem(at: folder(agent.id))
        agents.removeAll { $0.id == agent.id }
    }

    /// "Agent 1", "Agent 2", … skipping names already taken.
    func freshName() -> String {
        let taken = Set(agents.map(\.name))
        var number = agents.count + 1
        while taken.contains("Agent \(number)") { number += 1 }
        return "Agent \(number)"
    }
}
