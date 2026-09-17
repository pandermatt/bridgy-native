import BridgyEngine
import SwiftUI
import UniformTypeIdentifiers

/// Runs every engine against every other and shows the table.
struct TournamentScreen: View {
    @Environment(AppModel.self) private var model

    @State private var configuration = TournamentConfiguration(minimumSize: 4, maximumSize: 5, gamesPerColour: 3)
    @State private var progress: Double = 0
    @State private var result: TournamentResult?
    @State private var runTask: Task<Void, Never>?
    @State private var exportURL: URL?

    private var isRunning: Bool { runTask != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                setupCard
                if isRunning { progressCard }
                if let result { resultsCard(result) }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background { BackdropView(backdrop: model.settings.backdrop) }
        .navigationTitle("Tournament")
        .onDisappear { cancel() }
    }

    // MARK: - Setup

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Every difficulty plays every other, in both colours, at each board size.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            stepper("Smallest board", value: $configuration.minimumSize, range: Board.minimumSize...12)
            stepper("Largest board", value: $configuration.maximumSize, range: Board.minimumSize...12)
            stepper("Games per colour", value: $configuration.gamesPerColour, range: 1...20)

            HStack {
                Label("\(configuration.totalGames(participants: Difficulty.allCases.count)) games", systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isRunning {
                    Button("Stop", systemImage: "stop.fill") { cancel() }
                        .buttonStyle(.glass)
                } else {
                    Button("Run", systemImage: "play.fill") { run() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isRunning)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: progress)
            Text("\(Int(progress * 100))% complete")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    // MARK: - Results

    private func resultsCard(_ result: TournamentResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Standings").font(.headline)
            ForEach(Array(result.standings.enumerated()), id: \.offset) { index, entry in
                HStack {
                    Text("\(index + 1).")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 24, alignment: .trailing)
                    Text(entry.name)
                    Spacer()
                    Text(entry.average, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                .font(.callout)
            }

            Divider()
            Text("Head to head").font(.headline)
            Text("Row's win rate against column.")
                .font(.caption)
                .foregroundStyle(.secondary)
            matrix(result)

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func matrix(_ result: TournamentResult) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(result.participants, id: \.self) { name in
                        Text(String(name.prefix(4)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(result.participants.enumerated()), id: \.offset) { row, name in
                    GridRow {
                        Text(name)
                            .font(.caption)
                            .gridColumnAlignment(.leading)
                        ForEach(result.participants.indices, id: \.self) { column in
                            if row == column {
                                Text("—").font(.caption2).foregroundStyle(.tertiary)
                            } else {
                                Text(result.winRate[row][column], format: .percent.precision(.fractionLength(0)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(result.winRate[row][column] >= 0.5 ? .primary : .secondary)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Running

    private func run() {
        cancel()
        progress = 0
        result = nil
        exportURL = nil
        let settings = configuration
        runTask = Task {
            let participants = Tournament.defaultParticipants(forSize: settings.maximumSize)
            let outcome = await Tournament.run(
                configuration: settings,
                participants: participants,
                onProgress: { fraction in
                    Task { @MainActor in progress = fraction }
                }
            )
            await MainActor.run {
                runTask = nil
                guard let outcome else { return }
                result = outcome
                exportURL = writeCSV(outcome)
            }
        }
    }

    private func cancel() {
        runTask?.cancel()
        runTask = nil
    }

    private func writeCSV(_ result: TournamentResult) -> URL? {
        let url = URL.temporaryDirectory.appendingPathComponent("bridgy-tournament.csv")
        guard let data = result.csv().data(using: .utf8) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }
}
