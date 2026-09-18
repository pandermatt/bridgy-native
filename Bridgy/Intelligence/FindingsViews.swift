import AppIntents
import BridgyEngine
import SwiftUI

/// The experiment written up, with the facts every statement rests on.
struct FindingsSections: View {
    let analysis: ExperimentAnalysis
    @Environment(AppModel.self) private var model
    @State private var working = false
    @State private var error: String?
    @State private var facts: [Fact] = []

    private var findings: Findings? { analysis.experiment.findings }

    var body: some View {
        Section {
            if let findings {
                Text(findings.headline).font(.headline)
                ForEach(findings.findings) { finding in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(finding.statement)
                        evidence(for: finding, in: findings)
                    }
                    .padding(.vertical, 2)
                }
                callout("Caveat", findings.caveat, symbol: "exclamationmark.triangle", tint: .orange)
                callout("Next experiment", findings.nextExperiment, symbol: "arrow.forward.circle", tint: .accentColor)
            } else {
                Text("Nothing written yet.").foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    Task { await write() }
                } label: {
                    Label(working ? "Writing…" : findings == nil ? "Write Findings" : "Rewrite",
                          systemImage: "apple.intelligence")
                }
                .disabled(working || analysis.games.isEmpty)
                if working { ProgressView().controlSize(.small) }
            }
            if case .unavailable(let reason) = FindingsWriter.availability {
                Text("\(reason) Until then, findings are arranged from the facts by a plain template.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            }
            #if os(iOS)
            SiriTipView(intent: SummarizeExperimentIntent())
            #else
            Label("Ask Siri about this experiment — it can read the report on screen.", systemImage: "mic")
                .font(.caption).foregroundStyle(.secondary)
            #endif
        } header: {
            Text("Findings")
        } footer: {
            if let findings {
                Text(findings.byModel
                     ? "Written on this device by Apple Intelligence \(findings.written.formatted(.relative(presentation: .named))), using only the facts below. The evidence under each finding is the app's own figure, not the model's."
                     : "Arranged from the facts below by a template.")
            }
        }

        Section {
            DisclosureGroup("All \(facts.count) facts") {
                ForEach(facts) { fact in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(fact.id).font(.caption.monospaced()).foregroundStyle(.secondary).fixedSize().frame(minWidth: 30, alignment: .leading)
                        Text(fact.text).font(.callout).textSelection(.enabled)
                    }
                }
            }
        } header: {
            Text("Facts")
        } footer: {
            Text("Computed by the app from the games. This is all the model is shown.")
        }
        .task(id: analysis.games.count) { facts = FactSheet.facts(for: analysis) }
    }

    private func evidence(for finding: Findings.Finding, in findings: Findings) -> some View {
        let cited = finding.facts.compactMap(findings.fact)
        // The chip sits on the first line of its fact, in a fixed column, so a
        // two-line fact neither centres its chip nor pushes the text around.
        // More than two are folded away: the statement is the point.
        return Group {
            if cited.count > 2 {
                DisclosureGroup("\(cited.count) supporting facts") { evidenceRows(cited) }
                    .font(.caption)
            } else {
                evidenceRows(cited)
            }
        }
    }

    private func evidenceRows(_ cited: [Fact]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(cited) { fact in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(fact.id)
                        .font(.caption2.monospaced().weight(.semibold))
                        .fixedSize()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                        .frame(width: 38, alignment: .leading)
                    Text(fact.text).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Caveat and next step: part of the write-up, so full weight, set apart by
    /// an icon rather than by greying them out.
    private func callout(_ title: String, _ text: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text)
            }
        }
    }

    private func write() async {
        working = true
        error = nil
        defer { working = false }
        var ratings: RatingAnalysis?
        if analysis.experiment.kind == .roundRobin {
            let games = analysis.bradleyTerryGames
            let count = analysis.names.count
            ratings = await Task.detached(priority: .userInitiated) {
                RatingAnalysis.run(games, participants: count, resamples: 200)
            }.value
        }
        let facts = FactSheet.facts(for: analysis, ratings: ratings)
        self.facts = facts
        var result: Findings
        if FindingsWriter.availability == .available {
            do {
                result = try await FindingsWriter.write(facts: facts)
            } catch {
                self.error = "Apple Intelligence couldn't write this up (\(error.localizedDescription)). Showing the template instead."
                result = FindingsWriter.template(facts: facts, analysis: analysis)
            }
        } else {
            result = FindingsWriter.template(facts: facts, analysis: analysis)
        }
        guard var experiment = model.library.experiment(analysis.experiment.id) else { return }
        experiment.findings = result
        model.library.save(experiment)
    }
}

/// A few sentences on how one game was won.
struct GameCommentaryView: View {
    let record: GameRecord
    let names: [String]
    @State private var text: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let text {
                Text(text).font(.callout)
            } else {
                Button {
                    Task { await commentate() }
                } label: {
                    Label(working ? "Commentating…" : "Commentate", systemImage: "apple.intelligence")
                }
                .disabled(working)
            }
        }
    }

    private func commentate() async {
        working = true
        defer { working = false }
        let facts = FindingsWriter.commentary(record: record, names: names)
        if FindingsWriter.availability == .available, let written = try? await FindingsWriter.narrate(facts) {
            text = written
        } else {
            text = facts.map(\.text).joined(separator: " ")
        }
    }
}
