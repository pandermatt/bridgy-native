import AppIntents
import BridgyEngine
import Charts
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// A finished export, ready for the save panel.
struct ExportedFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf, .plainText, .commaSeparatedText]
    let data: Data
    let contentType: UTType
    let filename: String

    init(data: Data, contentType: UTType, filename: String) {
        self.data = data
        self.contentType = contentType
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
        filename = configuration.file.filename ?? "Export"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// One experiment: its question, its results as they come in, every game, and
/// the statistics that say how far to trust them.
struct ExperimentDetail: View {
    let id: UUID
    @Environment(AppModel.self) private var model
    @State private var page: Page = .overview
    @State private var exporting: ExportedFile?

    enum Page: String, CaseIterable, Identifiable {
        case overview = "Overview", games = "Games", statistics = "Statistics", findings = "Findings"
        var id: String { rawValue }
    }

    private var experiment: Experiment? { model.library.experiment(id) }
    private var isRunning: Bool { model.runner.isRunning(id) }

    var body: some View {
        if let experiment {
            let games = model.runner.games(for: id, library: model.library)
            let analysis = ExperimentAnalysis(experiment: experiment, games: games)
            content(experiment, analysis: analysis)
                .navigationTitle(experiment.name)
                .toolbar { toolbar(experiment, analysis: analysis) }
                // Tells Siri which experiment is on screen, so "summarise
                // this" gets this report.
                .appEntityIdentifier(EntityIdentifier(for: ExperimentEntity.self, identifier: id))
                .fileExporter(
                    isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                    document: exporting,
                    contentType: exporting?.contentType ?? .plainText,
                    defaultFilename: exporting?.filename
                ) { _ in exporting = nil }
        } else {
            ContentUnavailableView("Experiment deleted", systemImage: "flask")
        }
    }

    @ViewBuilder
    private func content(_ experiment: Experiment, analysis: ExperimentAnalysis) -> some View {
        switch page {
        case .games:
            VStack(spacing: 0) {
                pagePicker.padding()
                GamesView(analysis: analysis)
            }
        default:
            Form {
                Section { pagePicker.listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
                header(experiment, analysis: analysis)
                switch page {
                case .overview: overview(analysis)
                case .statistics: StatisticsSections(analysis: analysis)
                case .findings: FindingsSections(analysis: analysis)
                case .games: EmptyView()
                }
            }
            .formStyle(.grouped)
        }
    }

    private var pagePicker: some View {
        Picker("Page", selection: $page) {
            ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Header

    private func header(_ experiment: Experiment, analysis: ExperimentAnalysis) -> some View {
        Section {
            Text(experiment.question).font(.headline)
            if isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    if experiment.kind == .hypothesis {
                        ProgressView().progressViewStyle(.linear)
                    } else {
                        ProgressView(value: Double(analysis.games.count), total: Double(max(experiment.scheduledGames, 1)))
                    }
                    Text(progressText(experiment, played: analysis.games.count))
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if let error = model.runner.error, !isRunning {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote)
            }
            LabeledContent("Played", value: "\(analysis.games.count) games")
            LabeledContent("Seed") {
                Text(String(format: "%016llX", experiment.seed)).monospaced().textSelection(.enabled)
            }
        } footer: {
            Text("\(experiment.kind.title) · \(experiment.created.formatted(date: .abbreviated, time: .shortened)) · Bridgy \(experiment.appVersion)")
        }
    }

    private func progressText(_ experiment: Experiment, played: Int) -> String {
        experiment.kind == .hypothesis
            ? "\(played) games — running until the test decides"
            : "\(played) of \(experiment.scheduledGames) games"
    }

    @ToolbarContentBuilder
    private func toolbar(_ experiment: Experiment, analysis: ExperimentAnalysis) -> some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button { export(.pdf, analysis) } label: { Label("Report (PDF)…", systemImage: "doc.text") }
                Button { export(.markdown, analysis) } label: { Label("Report (Markdown)…", systemImage: "doc.richtext") }
                Button { export(.csv, analysis) } label: { Label("All Games (CSV)…", systemImage: "tablecells") }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(analysis.games.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            if isRunning {
                Button(role: .destructive) { model.runner.stop(library: model.library) } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            } else {
                Button { model.runner.start(experiment, library: model.library, agents: model.agents) } label: {
                    Label(experiment.gamesPlayed > 0 ? "Run Again" : "Run", systemImage: "play.fill")
                }
                .disabled(model.runner.isRunning)
            }
        }
    }

    // MARK: - Export

    private enum ExportFormat { case pdf, markdown, csv }

    private func export(_ format: ExportFormat, _ analysis: ExperimentAnalysis) {
        let name = analysis.experiment.name.replacingOccurrences(of: "/", with: "-")
        switch format {
        case .pdf:
            guard let url = try? ReportDocument.pdf(analysis, theme: model.settings.theme),
                  let data = try? Data(contentsOf: url) else { return }
            exporting = ExportedFile(data: data, contentType: .pdf, filename: "\(name).pdf")
        case .markdown:
            exporting = ExportedFile(data: Data(ReportWriter.markdown(analysis).utf8),
                                     contentType: .plainText, filename: "\(name).md")
        case .csv:
            exporting = ExportedFile(data: Data(ReportWriter.csv(analysis).utf8),
                                     contentType: .commaSeparatedText, filename: "\(name) games.csv")
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private func overview(_ analysis: ExperimentAnalysis) -> some View {
        switch analysis.experiment.kind {
        case .roundRobin: RoundRobinOverview(analysis: analysis.tournament)
        case .mirror: MirrorOverview(analysis: analysis)
        case .hypothesis: HypothesisOverview(analysis: analysis)
        }
    }
}

// MARK: - Mirror

struct MirrorOverview: View {
    let analysis: ExperimentAnalysis
    @State private var focus: String?

    var body: some View {
        let points = analysis.mirrorBySize
        Section {
            Picker("Show intervals for", selection: $focus) {
                Text("All engines").tag(String?.none)
                ForEach(analysis.names, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Board size", point.size), y: .value("Down wins", point.record.rate))
                        .foregroundStyle(by: .value("Engine", point.series))
                        .opacity(focus == nil || focus == point.series ? 1 : 0.15)
                    PointMark(x: .value("Board size", point.size), y: .value("Down wins", point.record.rate))
                        .foregroundStyle(by: .value("Engine", point.series))
                        .opacity(focus == nil || focus == point.series ? 1 : 0.15)
                    if focus == point.series {
                        RuleMark(x: .value("Board size", point.size),
                                 yStart: .value("Low", point.record.interval.low),
                                 yEnd: .value("High", point.record.interval.high))
                            .foregroundStyle(by: .value("Engine", point.series))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .opacity(0.5)
                    }
                }
                RuleMark(y: .value("Even", 0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis { AxisMarks(format: Decimal.FormatStyle.Percent.percent.precision(.fractionLength(0))) }
            .chartXScale(domain: (analysis.experiment.sizes.min() ?? 2)...max((analysis.experiment.sizes.max() ?? 3), (analysis.experiment.sizes.min() ?? 2) + 1))
            .chartXAxis { AxisMarks(values: analysis.experiment.sizes) }
            .chartXAxisLabel("Board size")
            .frame(height: 260)
            .padding(.vertical, 4)
        } header: {
            Text("Down's win rate playing itself")
        } footer: {
            Text("Above the dashed line, moving first helps that engine. Perfect sits at 100%: it knows the winning strategy. For the rest, the advantage is only as large as their play is good enough to use it.")
        }

        Section("By engine") {
            ForEach(analysis.names, id: \.self) { name in
                let own = points.filter { $0.series == name }
                let wins = own.reduce(0) { $0 + $1.record.wins }
                let games = own.reduce(0) { $0 + $1.record.games }
                let record = Record(wins: wins, games: games)
                LabeledContent(name) {
                    Text("\(Int((record.rate * 100).rounded()))%  \(record.interval.description())")
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: - Hypothesis

struct HypothesisOverview: View {
    let analysis: ExperimentAnalysis

    var body: some View {
        if let evidence = analysis.evidence, let h = analysis.experiment.hypothesis {
            let test = evidence.test
            Section {
                Label(verdict(test, h), systemImage: symbol(test.decision))
                    .font(.headline)
                    .foregroundStyle(test.decision == .undecided ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                let record = Record(wins: test.wins, games: test.games)
                LabeledContent("Won") {
                    Text("\(test.wins) of \(test.games) · \(Int((record.rate * 100).rounded()))% \(record.interval.description())")
                        .monospacedDigit()
                }
            } header: {
                Text("Verdict")
            }
            Section {
                Chart {
                    ForEach(evidence.path) { point in
                        LineMark(x: .value("Games", point.games), y: .value("Evidence", point.logLikelihoodRatio))
                    }
                    RuleMark(y: .value("Accept", test.upperBound))
                        .foregroundStyle(.green)
                        .annotation(position: .top, alignment: .leading) { Text("claim holds").font(.caption2) }
                    RuleMark(y: .value("Reject", test.lowerBound))
                        .foregroundStyle(.red)
                        .annotation(position: .bottom, alignment: .leading) { Text("claim fails").font(.caption2) }
                }
                .chartXAxisLabel("Games")
                .frame(height: 220)
                .padding(.vertical, 4)
            } header: {
                Text("Evidence")
            } footer: {
                Text("The log-likelihood ratio of “at least \(Int(h.p1 * 100))%” against “at most \(Int(h.p0 * 100))%”. Each win moves it up, each loss down; the test ends when it crosses a line. Error rates: \(Int(h.alpha * 100))% each way.")
            }
        }
    }

    private func verdict(_ test: SequentialTest, _ h: Experiment.Hypothesis) -> String {
        switch test.decision {
        case .acceptH1: "Supported: it wins at least \(Int(h.p1 * 100))% of the time."
        case .acceptH0: "Rejected: it wins at most \(Int(h.p0 * 100))% of the time."
        case .undecided: "Not decided yet."
        }
    }

    private func symbol(_ decision: SequentialTest.Decision) -> String {
        switch decision {
        case .acceptH1: "checkmark.seal.fill"
        case .acceptH0: "xmark.seal.fill"
        case .undecided: "hourglass"
        }
    }
}

// MARK: - Statistics

struct StatisticsSections: View {
    let analysis: ExperimentAnalysis
    @State private var ratings: RatingAnalysis?
    @State private var ratedCount = -1

    var body: some View {
        firstPlayerSection
        if analysis.experiment.kind != .mirror {
            ratingsSection
            pairingsSection
        }
        planningSection
    }

    private var firstPlayerSection: some View {
        Section {
            ForEach(analysis.firstPlayerBySize) { point in
                LabeledContent("\(point.size)×\(point.size)") {
                    Text("\(Int((point.record.rate * 100).rounded()))%  \(point.record.interval.description())  n=\(point.record.games)")
                        .monospacedDigit()
                        .foregroundStyle(point.record.interval.low > 0.5 ? .primary : .secondary)
                }
            }
        } header: {
            Text("Down wins, by size")
        } footer: {
            Text("Every pairing plays both colours equally, so this is the first-player advantage in this field with nothing mixed in. Dimmed rows have an interval reaching 50%: at that sample size the advantage could be nothing.")
        }
    }

    private var ratingsSection: some View {
        Section {
            if let ratings {
                let order = analysis.names.indices.sorted { ratings.fit.ratings[$0] > ratings.fit.ratings[$1] }
                ForEach(order, id: \.self) { index in
                    let interval = ratings.ratingIntervals[index]
                    LabeledContent(analysis.names[index]) {
                        Text("\(Int(ratings.fit.ratings[index].rounded()))  [\(Int(interval.low.rounded()))–\(Int(interval.high.rounded()))]")
                            .monospacedDigit()
                    }
                }
            } else {
                ProgressView("Fitting…")
            }
        } header: {
            Text("Ratings")
        } footer: {
            Text("Bradley–Terry strengths fitted to all games at once, on the Elo scale, with 95% bootstrap intervals (200 resamples). Unlike running Elo, the order games were played in makes no difference.")
        }
        .task(id: analysis.games.count / 25) { await fit() }
    }

    private func fit() async {
        guard analysis.games.count != ratedCount else { return }
        let games = analysis.bradleyTerryGames
        let count = analysis.names.count
        let result = await Task.detached(priority: .utility) {
            RatingAnalysis.run(games, participants: count, resamples: 200)
        }.value
        ratings = result
        ratedCount = analysis.games.count
    }

    private var pairingsSection: some View {
        Section {
            ForEach(analysis.pairings) { pairing in
                LabeledContent {
                    HStack(spacing: 6) {
                        Text("\(pairing.record.wins)–\(pairing.record.games - pairing.record.wins)").monospacedDigit()
                        Text(pairing.adjusted < 0.001 ? "p<0.001" : String(format: "p=%.3f", pairing.adjusted))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(pairing.isSignificant ? .primary : .secondary)
                        Image(systemName: pairing.isSignificant ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(pairing.isSignificant ? .green : .secondary)
                    }
                } label: {
                    Text("\(analysis.names[pairing.row]) v \(analysis.names[pairing.column])")
                }
            }
        } header: {
            Text("Pairings")
        } footer: {
            Text("Exact binomial test of each pairing against an even split, Holm-adjusted for testing every pairing at once. A tick means the difference would be surprising if the two were equal.")
        }
    }

    private var planningSection: some View {
        Section {
            ForEach([0.1, 0.05, 0.025], id: \.self) { width in
                LabeledContent("±\(Int(width * 100)) points") {
                    Text("\(Significance.gamesNeeded(halfWidth: width)) games").monospacedDigit()
                }
            }
        } header: {
            Text("Planning")
        } footer: {
            Text("Games needed per cell for a 95% interval of that width around a 50% rate.")
        }
    }
}
