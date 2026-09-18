import BridgyEngine
import Foundation

/// An experiment as a document: what was asked, how, what came out, and
/// everything needed to reproduce it.
///
/// One text serves three readers — the exported report, the CSV's companion,
/// and Siri when asked about the experiment on screen.
enum ReportWriter {

    static func markdown(_ analysis: ExperimentAnalysis) -> String {
        let e = analysis.experiment
        var out: [String] = []
        out.append("# \(e.name)")
        out.append("")
        out.append("**Question.** \(e.question)")
        out.append("")

        if let findings = e.findings {
            out.append("## Findings")
            out.append("")
            out.append("**\(findings.headline)**")
            out.append("")
            for finding in findings.findings {
                let evidence = finding.facts.compactMap(findings.fact).map { "\($0.id): \($0.text)" }
                out.append("- \(finding.statement)")
                for line in evidence { out.append("  - _\(line)_") }
            }
            out.append("")
            out.append("*Caveat.* \(findings.caveat)")
            out.append("")
            out.append("*Next.* \(findings.nextExperiment)")
            out.append("")
            out.append(findings.byModel
                       ? "_Written on device by Apple Intelligence from the facts below; figures under each finding are computed by the app._"
                       : "_Arranged from the facts below by a template._")
            out.append("")
        }

        out.append("## Method")
        out.append("")
        out.append("- Design: \(e.kind.title). \(e.kind.summary)")
        out.append("- Participants: \(e.entrants.map(entrantLine).joined(separator: "; "))")
        out.append("- Board sizes: \(e.sizeText)")
        switch e.kind {
        case .roundRobin: out.append("- Games per colour per pairing per size: \(e.gamesPerUnit)")
        case .mirror: out.append("- Games per engine per size: \(e.gamesPerUnit)")
        case .hypothesis:
            if let h = e.hypothesis {
                out.append("- Sequential probability ratio test: H0 rate ≤ \(pct(h.p0)), H1 rate ≥ \(pct(h.p1)), α = \(h.alpha), β = \(h.beta), at most \(h.maxGames) games")
            }
        }
        out.append("- Games played: \(analysis.games.count)")
        out.append("- Intervals: 95% Wilson score; ratings: Bradley–Terry with 95% bootstrap intervals; pairings: exact binomial, Holm-corrected")
        out.append("")

        out.append("## Results")
        out.append("")
        for fact in FactSheet.facts(for: analysis) {
            out.append("- \(fact.id): \(fact.text)")
        }
        out.append("")

        out.append("## Reproducibility")
        out.append("")
        out.append("- Seed: `\(String(format: "%016llX", e.seed))` (game *i* is played from SplitMix(seed, i))")
        out.append("- Bridgy \(e.appVersion)")
        out.append("- Created \(e.created.formatted(.iso8601))")
        out.append("- Every game's moves are included in the accompanying CSV.")
        return out.joined(separator: "\n")
    }

    /// Every game, one per line, moves as cell indices.
    static func csv(_ analysis: ExperimentAnalysis) -> String {
        var lines = ["game;size;down;across;winner;moves;seed;move_cells"]
        for game in analysis.games.sorted(by: { $0.index < $1.index }) {
            lines.append([
                "\(game.index + 1)", "\(game.size)",
                analysis.names[game.down], analysis.names[game.across],
                game.winner.displayName, "\(game.length)",
                String(format: "%016llX", game.seed),
                game.moves.map(String.init).joined(separator: " ")
            ].joined(separator: ";"))
        }
        return lines.joined(separator: "\n")
    }

    private static func entrantLine(_ entrant: Experiment.Entrant) -> String {
        if let hash = entrant.weightsHash { return "\(entrant.name) (trained network \(hash))" }
        return entrant.name
    }

    private static func pct(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}
