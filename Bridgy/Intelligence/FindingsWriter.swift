import BridgyEngine
import Foundation
import FoundationModels

/// Writes up an experiment, on device, from facts the app computed.
///
/// The model is handed the fact table and asked for a headline and a few
/// findings, each citing the facts it rests on. Its prose is kept; its numbers
/// are not trusted — the screen shows the cited facts themselves beside every
/// finding, and a finding citing nothing real is dropped. Without Apple
/// Intelligence the same facts go through a plain template instead.
enum FindingsWriter {

    @Generable
    struct Draft {
        @Guide(description: "One plain sentence stating the single most important result.")
        var headline: String
        @Guide(description: "Two to four findings, most important first. Each must rest on facts from the table. Prefer trends, contrasts and surprises over restating numbers.")
        var findings: [DraftFinding]
        @Guide(description: "One sentence on what these data cannot show, such as small samples or wide intervals.")
        var caveat: String
        @Guide(description: "One follow-up experiment, in a sentence, that would sharpen the answer.")
        var nextExperiment: String
    }

    @Generable
    struct DraftFinding {
        @Guide(description: "The finding, in one or two plain sentences, with at most two numbers quoted exactly as the facts give them. The cited facts are shown beside it, so do not list every figure.")
        var statement: String
        @Guide(description: "IDs of the facts this finding rests on, such as F3.")
        var facts: [String]
    }

    enum Availability: Equatable {
        case available
        case unavailable(String)
    }

    static var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in Settings for written findings.")
        case .unavailable(.deviceNotEligible):
            return .unavailable("This device doesn't support Apple Intelligence.")
        case .unavailable(.modelNotReady):
            return .unavailable("Apple Intelligence is still getting ready. Try again shortly.")
        case .unavailable:
            return .unavailable("Apple Intelligence isn't available.")
        }
    }

    static let instructions = """
        You are a careful research assistant summarising experiments with Bridg-It, \
        a two-player connection game in which Down moves first and needs a top-to-bottom \
        chain, and Across needs a left-to-right chain. It is proven that a perfect first \
        player always wins. You are given numbered facts computed by the app. Use only \
        those facts. Never invent numbers, engines or results. Quote percentages and \
        intervals exactly as written. Treat a result whose interval includes 50% as \
        uncertain, and a change whose intervals overlap as possibly noise. Explain what \
        the results mean rather than listing them. Write plainly for a curious reader, \
        not a statistician.
        """

    /// Findings from the model, validated against the facts.
    static func write(facts: [Fact]) async throws -> Findings {
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Facts:\n\(FactSheet.table(facts))\n\nSummarise what this experiment found."
        let draft = try await session.respond(to: prompt, generating: Draft.self).content
        let known = Set(facts.map(\.id))
        let findings = draft.findings.compactMap { finding -> Findings.Finding? in
            let cited = finding.facts
                .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
                .filter(known.contains)
            guard !cited.isEmpty else { return nil }
            return Findings.Finding(statement: finding.statement, facts: cited)
        }
        return Findings(
            headline: draft.headline, findings: findings, caveat: draft.caveat,
            nextExperiment: draft.nextExperiment, byModel: true, written: .now, facts: facts
        )
    }

    /// The same facts, arranged without a model.
    static func template(facts: [Fact], analysis: ExperimentAnalysis) -> Findings {
        let body = Array(facts.dropFirst().prefix(4))
        let small = analysis.games.count < 100
        return Findings(
            headline: facts.dropFirst().first?.text ?? "No games have been played yet.",
            findings: body.map { Findings.Finding(statement: $0.text, facts: [$0.id]) },
            caveat: small
                ? "Few games so far: treat any difference whose interval overlaps 50% as unproven."
                : "Results hold for these engines and board sizes only.",
            nextExperiment: analysis.experiment.kind == .mirror
                ? "Test the smallest advantage you see with a hypothesis test at that size."
                : "Run mirror matches at the sizes where the first-player rate is least certain.",
            byModel: false, written: .now, facts: facts
        )
    }

    // MARK: - Game commentary

    @Generable
    struct Commentary {
        @Guide(description: "Two or three sentences on how the game was won. Refer to the sides as Down and Across, name the turning points by move number, and say who won exactly as the facts do.")
        var text: String
    }

    static func commentary(record: GameRecord, names: [String]) -> [Fact] {
        let down = names[record.down], across = names[record.across]
        let winner = record.winner.displayName
        let loser = record.winner.opponent.displayName
        var lines = [
            "Down (moving first, building top to bottom) was played by \(down). Across (building left to right) was played by \(across).",
            "\(winner) won: it completed its chain on move \(record.length) of a \(record.size)×\(record.size) board, and \(loser) lost."
        ]
        func needed(_ value: Int?) -> String { value.map { "\($0)" } ?? "no route left" }
        for turn in RaceHistory.turningPoints(record) {
            let mover = turn.move % 2 == 1 ? "Down" : "Across"
            lines.append("Move \(turn.move) was played by \(mover). Before it, Down needed \(needed(turn.downBefore)) more moves and Across \(needed(turn.acrossBefore)); after it, Down needed \(needed(turn.downAfter)) and Across \(needed(turn.acrossAfter)).")
        }
        return lines.enumerated().map { Fact(id: "G\($0.offset + 1)", text: $0.element) }
    }

    static func narrate(_ facts: [Fact]) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Facts about one game:\n\(FactSheet.table(facts))\n\nDescribe how it was won."
        return try await session.respond(to: prompt, generating: Commentary.self).content.text
    }
}
