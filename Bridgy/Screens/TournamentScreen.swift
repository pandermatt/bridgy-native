import BridgyEngine
import BridgyTraining
import Charts
import SwiftUI

/// Every engine against every other, plotted while it runs.
struct TournamentScreen: View {
    @Environment(AppModel.self) private var model
    @State private var run = TournamentRun()
    @State private var focus: String?
    /// Which colour the size chart shows. Bridg-It is not colour-symmetric,
    /// so the combined figure hides the most important fact about Perfect.
    @State private var colour: Player?
    @State private var selectedGames: Int?

    var body: some View {
        Form {
            setupSection
            participantsSection
            if let analysis = run.analysis, analysis.gamesPlayed > 0 {
                ratingsSection(analysis)
                sizeSection(analysis)
                firstPlayerSection(analysis)
                headToHeadSection(analysis)
                exportSection
            }
        }
        // Was a bare List, which on macOS gave no grouped card at all: steppers
        // stretched edge to edge with their arrows pinned right, and the run
        // button fell back to a small default push button. This matches Settings
        // and Setup, which both already use it.
        .formStyle(.grouped)
        .navigationTitle("Tournament")
        .onDisappear { run.stop() }
    }

    // MARK: - Setup

    private var setupSection: some View {
        Section {
            // Plain Text labels, not LabeledContent: that expands to fill, which
            // is what pushed the stepper arrows to the far edge on macOS.
            Group {
                Stepper(
                    "Smallest board: \(run.configuration.minimumSize)",
                    value: $run.configuration.minimumSize,
                    in: Board.minimumSize...12
                )
                Stepper(
                    "Largest board: \(run.configuration.maximumSize)",
                    value: $run.configuration.maximumSize,
                    in: Board.minimumSize...12
                )
                Stepper(
                    "Games per colour: \(run.configuration.gamesPerColour)",
                    value: $run.configuration.gamesPerColour,
                    in: 1...50
                )
            }
            // Was on the last stepper alone, so the two board-size steppers
            // stayed live while a tournament was running.
            .disabled(run.isRunning)

            if run.isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: run.progress)
                    Text("\(run.analysis?.gamesPlayed ?? 0) of \(run.scheduledGames) games")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                // The label expands, not the Button: on macOS a frame on the
                // button widens its hit area but leaves the drawn control at its
                // intrinsic width.
                Button(role: .destructive) { run.stop() } label: {
                    Text("Stop").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button { run.start(store: model.agents) } label: {
                    Text("Run \(run.totalGames(store: model.agents)) Games").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(run.fieldSize(store: model.agents) < 2)
            }
        } header: {
            Text("Setup")
        } footer: {
            Text("Everyone in the field plays everyone else, in both colours, at each board size. Win rates carry 95% Wilson intervals, so small samples look small.")
        }
    }

    // MARK: - Participants

    private var participantsSection: some View {
        Section {
            ForEach(Difficulty.allCases) { level in
                Toggle(isOn: Binding(
                    get: { run.levels.contains(level) },
                    set: { if $0 { run.levels.insert(level) } else { run.levels.remove(level) } }
                )) {
                    Label(level.displayName, systemImage: level.symbolName)
                }
            }
            ForEach(model.agents.agents) { agent in
                Toggle(isOn: Binding(
                    get: { !run.benchedAgents.contains(agent.id) },
                    set: { if $0 { run.benchedAgents.remove(agent.id) } else { run.benchedAgents.insert(agent.id) } }
                )) {
                    Label {
                        VStack(alignment: .leading) {
                            Text(agent.name)
                            Text(agent.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "brain")
                    }
                }
            }
            NavigationLink {
                TrainingScreen(run: model.training)
            } label: {
                LabeledContent {
                    if model.training.isRunning {
                        Text("Round \(model.training.round) of \(model.training.roundsPlanned)").monospacedDigit()
                    }
                } label: {
                    Label("Train an Agent", systemImage: "brain.head.profile")
                }
            }
        } header: {
            Text("Participants")
        } footer: {
            Text("Agents you train join the field here. They search \(TrainingParameters().simulations) positions a move by default, so on large boards their games take a while.")
        }
        .disabled(run.isRunning)
    }

    // MARK: - Ratings

    private func ratingsSection(_ analysis: TournamentAnalysis) -> some View {
        Section {
            Chart(analysis.eloHistory) { sample in
                LineMark(
                    x: .value("Games", sample.games),
                    y: .value("Rating", sample.rating)
                )
                .foregroundStyle(by: .value("Engine", sample.participant))
                .interpolationMethod(.monotone)
                .opacity(focus == nil || focus == sample.participant ? 1 : 0.18)
            }
            .chartXSelection(value: $selectedGames)
            .chartYScale(domain: eloDomain(analysis))
            .chartYAxisLabel("Elo")
            .chartXAxisLabel("Games played")
            .frame(height: 240)
            .padding(.vertical, 4)

            if let selectedGames, let readout = ratingReadout(analysis, at: selectedGames) {
                Text(readout)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Ratings")
        } footer: {
            Text("Elo, updated after every game from 1500. Drag across the chart to read the ratings at a point. Lines that have stopped separating mean the field has settled.")
        }
    }

    /// Ratings span a few hundred points at most, so letting the axis start at
    /// zero flattens exactly the separation the chart exists to show.
    private func eloDomain(_ analysis: TournamentAnalysis) -> ClosedRange<Double> {
        let ratings = analysis.eloHistory.map(\.rating)
        guard let low = ratings.min(), let high = ratings.max(), high > low else {
            return 1_400...1_600
        }
        let padding = max(30, (high - low) * 0.12)
        return (low - padding)...(high + padding)
    }

    /// Ratings at the nearest sampled point to where the finger is.
    private func ratingReadout(_ analysis: TournamentAnalysis, at games: Int) -> String? {
        let candidates = Set(analysis.eloHistory.map(\.games))
        guard let nearest = candidates.min(by: { abs($0 - games) < abs($1 - games) }) else { return nil }
        let atPoint = analysis.eloHistory
            .filter { $0.games == nearest }
            .sorted { $0.rating > $1.rating }
        guard !atPoint.isEmpty else { return nil }
        let parts = atPoint.map { "\($0.participant) \(Int($0.rating.rounded()))" }
        return "After \(nearest): " + parts.joined(separator: " · ")
    }

    // MARK: - Board size

    private var sizeFooter: String {
        switch colour {
        case .blue?:
            "Moving first. Down can always force a win, and Perfect plays that strategy, so it should never lose here."
        case .red?:
            "Moving second. No strategy guarantees a win for Across, so here Perfect plays as Expert does."
        case nil:
            "How each engine holds up as the board grows. Split by colour to see where losses come from; pick an engine for its confidence intervals."
        }
    }

    private func sizeSection(_ analysis: TournamentAnalysis) -> some View {
        Section {
            Picker("Show intervals for", selection: $focus) {
                Text("All engines").tag(String?.none)
                ForEach(analysis.participants, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
            }
            .pickerStyle(.menu)

            Picker("Playing", selection: $colour) {
                Text("Both").tag(Player?.none)
                Text("As Down").tag(Player?.some(.blue))
                Text("As Across").tag(Player?.some(.red))
            }
            .pickerStyle(.segmented)

            Chart {
                ForEach(analysis.sizePoints(as: colour)) { point in
                    LineMark(
                        x: .value("Board size", point.size),
                        y: .value("Win rate", point.record.rate)
                    )
                    .foregroundStyle(by: .value("Engine", point.participant))
                    .opacity(focus == nil || focus == point.participant ? 1 : 0.18)

                    PointMark(
                        x: .value("Board size", point.size),
                        y: .value("Win rate", point.record.rate)
                    )
                    .foregroundStyle(by: .value("Engine", point.participant))
                    .opacity(focus == nil || focus == point.participant ? 1 : 0.18)

                    // Whiskers only for the focused engine: six overlapping
                    // intervals at each size is unreadable.
                    if focus == point.participant {
                        RuleMark(
                            x: .value("Board size", point.size),
                            yStart: .value("Low", point.record.interval.low),
                            yEnd: .value("High", point.record.interval.high)
                        )
                        .foregroundStyle(by: .value("Engine", point.participant))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .opacity(0.5)
                    }
                }
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(format: Decimal.FormatStyle.Percent.percent.precision(.fractionLength(0)))
            }
            // Without an explicit domain the axis starts at zero and squeezes
            // every point into the right-hand edge.
            .chartXScale(domain: sizeDomain(analysis))
            .chartXAxis {
                AxisMarks(values: analysis.configuration.sizes)
            }
            .chartXAxisLabel("Board size")
            .frame(height: 220)
            .padding(.vertical, 4)
        } header: {
            Text("Win rate by board size")
        } footer: {
            Text(sizeFooter)
        }
    }

    private func sizeDomain(_ analysis: TournamentAnalysis) -> ClosedRange<Int> {
        let sizes = analysis.configuration.sizes
        guard let low = sizes.first, let high = sizes.last, high > low else {
            return (sizes.first ?? 2)...((sizes.last ?? 2) + 1)
        }
        return low...high
    }

    // MARK: - First player

    private func firstPlayerSection(_ analysis: TournamentAnalysis) -> some View {
        Section {
            Chart {
                ForEach(analysis.firstPlayerPoints) { point in
                    BarMark(
                        x: .value("Board size", "\(point.size)"),
                        y: .value("First-player win rate", point.record.rate)
                    )
                    .foregroundStyle(model.settings.theme.color(for: .blue).opacity(0.75))

                    RuleMark(
                        x: .value("Board size", "\(point.size)"),
                        yStart: .value("Low", point.record.interval.low),
                        yEnd: .value("High", point.record.interval.high)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .foregroundStyle(.primary)
                }
                RuleMark(y: .value("Even", 0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(format: Decimal.FormatStyle.Percent.percent.precision(.fractionLength(0)))
            }
            .frame(height: 200)
            .padding(.vertical, 4)
        } header: {
            Text("First-player advantage")
        } footer: {
            Text("Down moves first, and Bridg-It is provably a first-player win, so these bars should sit above the dashed line. If they do not, the field is too weak to exploit it — or something is wrong.")
        }
    }

    // MARK: - Head to head

    private func headToHeadSection(_ analysis: TournamentAnalysis) -> some View {
        Section {
            ScrollView(.horizontal) {
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        ForEach(analysis.participants, id: \.self) { name in
                            Text(String(name.prefix(4)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(analysis.participants.enumerated()), id: \.offset) { row, name in
                        GridRow {
                            Text(name).font(.caption).gridColumnAlignment(.leading)
                            ForEach(analysis.participants.indices, id: \.self) { column in
                                if row == column {
                                    Text("—").font(.caption2).foregroundStyle(.tertiary)
                                } else {
                                    let record = analysis.head(row, against: column)
                                    VStack(spacing: 1) {
                                        Text(record.rate, format: .percent.precision(.fractionLength(0)))
                                            .font(.caption.monospacedDigit())
                                        Text(record.interval.description())
                                            .font(.system(size: 8).monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            ForEach(Array(analysis.standings.enumerated()), id: \.offset) { index, entry in
                LabeledContent {
                    Text("\(Int(entry.rating.rounded()))").monospacedDigit()
                } label: {
                    HStack {
                        Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                        Text(entry.name)
                    }
                }
            }
        } header: {
            Text("Head to head")
        } footer: {
            Text("Row's win rate against column, with its 95% interval underneath.")
        }
    }

    private var exportSection: some View {
        Section {
            if let report = run.report {
                ShareLink(item: report, preview: SharePreview("Tournament results")) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
