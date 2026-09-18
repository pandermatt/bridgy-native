import BridgyEngine
import Charts
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// The experiment as a printable page: the same content as the Markdown
/// report, with the key chart drawn in.
struct ReportDocument: View {
    let analysis: ExperimentAnalysis
    let theme: BoardTheme

    private var experiment: Experiment { analysis.experiment }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(experiment.name).font(.largeTitle.bold())
                Text(experiment.question).font(.title3)
                Text("\(experiment.kind.title) · \(analysis.games.count) games · \(experiment.created.formatted(date: .long, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let findings = experiment.findings {
                section("Findings") {
                    Text(findings.headline).font(.headline)
                    ForEach(findings.findings) { finding in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("• \(finding.statement)")
                            ForEach(finding.facts.compactMap(findings.fact)) { fact in
                                Text("\(fact.id): \(fact.text)").font(.caption).foregroundStyle(.secondary)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    Text("Caveat: \(findings.caveat)").font(.callout)
                    Text("Next: \(findings.nextExperiment)").font(.callout)
                    Text(findings.byModel
                         ? "Written on device by Apple Intelligence from the facts below; the figures under each finding are the app's own."
                         : "Arranged from the facts below by a template.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            section(chartTitle) { chart.frame(height: 220) }

            section("Results") {
                ForEach(FactSheet.facts(for: analysis)) { fact in
                    Text("\(fact.id)  \(fact.text)").font(.callout)
                }
            }

            section("Method and reproducibility") {
                Text(experiment.kind.summary)
                Text("Participants: \(experiment.entrants.map { entrant in entrant.weightsHash.map { "\(entrant.name) (\($0))" } ?? entrant.name }.joined(separator: ", ")). Board sizes \(experiment.sizeText).")
                Text("95% Wilson intervals; Bradley–Terry ratings with bootstrap intervals; exact binomial tests, Holm-corrected.")
                Text("Seed \(String(format: "%016llX", experiment.seed)) · Bridgy \(experiment.appVersion). Every game's moves are in the CSV export.")
            }
            .font(.callout)
        }
        .padding(40)
        .frame(width: 612, alignment: .leading)
        .background(.white)
        .environment(\.colorScheme, .light)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.bold())
            content()
        }
    }

    private var chartTitle: String {
        experiment.kind == .mirror ? "Down's win rate playing itself" : "Down's win rate by board size"
    }

    @ViewBuilder
    private var chart: some View {
        let points = experiment.kind == .mirror ? analysis.mirrorBySize : analysis.firstPlayerBySize
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Board size", point.size), y: .value("Down wins", point.record.rate))
                    .foregroundStyle(by: .value("Engine", point.series))
                PointMark(x: .value("Board size", point.size), y: .value("Down wins", point.record.rate))
                    .foregroundStyle(by: .value("Engine", point.series))
                if experiment.kind != .mirror {
                    RuleMark(x: .value("Board size", point.size),
                             yStart: .value("Low", point.record.interval.low),
                             yEnd: .value("High", point.record.interval.high))
                        .foregroundStyle(theme.color(for: .blue))
                }
            }
            RuleMark(y: .value("Even", 0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.gray)
        }
        .chartYScale(domain: 0...1)
        .chartYAxis { AxisMarks(format: Decimal.FormatStyle.Percent.percent.precision(.fractionLength(0))) }
        .chartXAxis { AxisMarks(values: experiment.sizes) }
    }

    /// Renders the page to a PDF file, one page as tall as the content.
    @MainActor
    static func pdf(_ analysis: ExperimentAnalysis, theme: BoardTheme) throws -> URL {
        let name = analysis.experiment.name.replacingOccurrences(of: "/", with: "-")
        let url = URL.temporaryDirectory.appendingPathComponent("\(name).pdf")
        let renderer = ImageRenderer(content: ReportDocument(analysis: analysis, theme: theme))
        renderer.proposedSize = ProposedViewSize(width: 612, height: nil)
        var failed = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { failed = true; return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        if failed { throw CocoaError(.fileWriteUnknown) }
        return url
    }
}
