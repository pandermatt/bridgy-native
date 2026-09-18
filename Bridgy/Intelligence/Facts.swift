import BridgyEngine
import Foundation

/// One number the app vouches for, with an ID a summary can cite.
struct Fact: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let text: String
}

/// The facts an experiment establishes, computed by the app — never by the
/// language model, which only gets to choose among them and phrase them.
enum FactSheet {

    static func facts(for analysis: ExperimentAnalysis, ratings: RatingAnalysis? = nil) -> [Fact] {
        var lines: [String] = []
        let e = analysis.experiment
        let games = analysis.games
        lines.append("Question: \(e.question) \(games.count) games were played (\(e.kind.title)).")

        func pct(_ r: Record) -> String {
            "\(Int((r.rate * 100).rounded()))% (95% CI \(r.interval.description()), \(r.wins) of \(r.games))"
        }

        switch e.kind {
        case .roundRobin:
            let t = analysis.tournament
            if let ratings {
                let order = analysis.names.indices.sorted { ratings.fit.ratings[$0] > ratings.fit.ratings[$1] }
                for (rank, i) in order.enumerated() {
                    let ci = ratings.ratingIntervals[i]
                    lines.append("\(analysis.names[i]) ranks \(rank + 1) with a Bradley–Terry rating of \(Int(ratings.fit.ratings[i].rounded())) (95% CI \(Int(ci.low.rounded()))–\(Int(ci.high.rounded()))).")
                }
            }
            for (i, name) in analysis.names.enumerated() {
                lines.append("\(name) wins \(pct(t.overall[i])) of all its games.")
                let down = t.record(of: i, as: .blue), across = t.record(of: i, as: .red)
                if !down.isEmpty, !across.isEmpty {
                    lines.append("\(name) wins \(pct(down)) as Down (moving first) and \(pct(across)) as Across.")
                }
            }
            for pairing in analysis.pairings where pairing.isSignificant {
                let a = analysis.names[pairing.row], b = analysis.names[pairing.column]
                lines.append("\(a) beats \(b) in \(pct(pairing.record)); significant after Holm correction (p=\(String(format: "%.3g", pairing.adjusted))).")
            }
            let even = analysis.pairings.filter { !$0.isSignificant }
            if !even.isEmpty {
                let names = even.map { "\(analysis.names[$0.row]) v \(analysis.names[$0.column])" }
                lines.append("No significant difference was found for: \(names.formatted()).")
            }
        case .mirror:
            for name in analysis.names {
                let own = analysis.mirrorBySize.filter { $0.series == name }
                guard let first = own.first, let last = own.last else { continue }
                let total = Record(wins: own.reduce(0) { $0 + $1.record.wins }, games: own.reduce(0) { $0 + $1.record.games })
                lines.append("Playing itself, \(name) wins as Down \(pct(total)) over all sizes.")
                if first.size != last.size {
                    lines.append(trend(name, from: first, to: last))
                }
            }
        case .hypothesis:
            if let evidence = analysis.evidence, let h = e.hypothesis {
                let r = Record(wins: evidence.test.wins, games: evidence.test.games)
                let verdict = switch evidence.test.decision {
                case .acceptH1: "supported (the rate is at least \(Int(h.p1 * 100))%)"
                case .acceptH0: "rejected (the rate is at most \(Int(h.p0 * 100))%)"
                case .undecided: "not yet decided"
                }
                lines.append("The claim was \(verdict) by a sequential test with \(Int(h.alpha * 100))% error rates after \(evidence.test.games) games.")
                lines.append("\(analysis.names[h.subject]) won \(pct(r)) against \(analysis.names[h.opponent]).")
            }
        }

        for point in analysis.firstPlayerBySize {
            let note = point.record.interval.low > 0.5 ? "clearly above half" : "not clearly above half"
            lines.append("On \(point.size)×\(point.size), Down (the first player) won \(pct(point.record)) — \(note).")
        }
        if games.count < 100 {
            lines.append("With only \(games.count) games, most intervals are wide.")
        }
        return lines.enumerated().map { Fact(id: "F\($0.offset + 1)", text: $0.element) }
    }

    /// How an engine's first-move advantage changes from the smallest board to
    /// the largest, and whether the change is more than noise (intervals that
    /// do not overlap).
    static func trend(_ name: String, from first: ExperimentAnalysis.SizeRecord, to last: ExperimentAnalysis.SizeRecord) -> String {
        let a = first.record, b = last.record
        let pa = Int((a.rate * 100).rounded()), pb = Int((b.rate * 100).rounded())
        if pa == pb {
            return "Playing itself, \(name)'s Down win rate is \(pa)% on both \(first.size)×\(first.size) and \(last.size)×\(last.size): no change."
        }
        let direction = pb < pa ? "falls" : "rises"
        let separated = a.interval.high < b.interval.low || b.interval.high < a.interval.low
        let verdict = separated
            ? "the intervals do not overlap, so the change is real"
            : "the intervals overlap, so the change may be noise"
        return "Playing itself, \(name)'s Down win rate \(direction) from \(pa)% on \(first.size)×\(first.size) (CI \(a.interval.description())) to \(pb)% on \(last.size)×\(last.size) (CI \(b.interval.description())); \(verdict)."
    }

    /// The facts as the model sees them, one per line.
    static func table(_ facts: [Fact]) -> String {
        facts.map { "\($0.id): \($0.text)" }.joined(separator: "\n")
    }
}

/// A summary whose every statement points back at facts.
struct Findings: Codable, Hashable, Sendable {
    struct Finding: Codable, Hashable, Sendable, Identifiable {
        var id: String { statement }
        let statement: String
        let facts: [String]
    }

    let headline: String
    let findings: [Finding]
    let caveat: String
    let nextExperiment: String
    /// Written by Apple Intelligence, or by the app's own template.
    let byModel: Bool
    let written: Date
    /// The facts as they stood when this was written. Citations point into
    /// these, never into a table recomputed later, whose numbering may differ.
    /// Optional only so findings saved before this existed still load.
    var facts: [Fact]?

    func fact(_ id: String) -> Fact? { facts?.first { $0.id == id } }
}
