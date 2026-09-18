import BridgyEngine
import Charts
import SwiftUI

/// Every game of an experiment, sortable, each one replayable.
struct GamesView: View {
    let analysis: ExperimentAnalysis
    @State private var selection: GameRecord.ID?
    @State private var order = [KeyPathComparator(\Row.index)]
    @State private var replaying: GameRecord?
    /// On iPhone: longest games first, five at a time.
    @State private var longestFirst = true
    @State private var showsAll = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    struct Row: Identifiable, Hashable {
        let record: GameRecord
        let down: String
        let across: String
        var id: Int { record.index }
        var index: Int { record.index }
        var size: Int { record.size }
        var length: Int { record.length }
        var winnerName: String { record.winner == .blue ? down : across }
        var colour: String { record.winner.displayName }
    }

    private var rows: [Row] {
        analysis.games.map { game in
            Row(record: game, down: analysis.names[game.down], across: analysis.names[game.across])
        }
        .sorted(using: order)
    }

    private var compact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if analysis.games.isEmpty {
                ContentUnavailableView("No games yet", systemImage: "square.grid.3x3", description: Text("Games appear here as they finish."))
            } else if compact {
                compactList
            } else {
                table
            }
        }
        .sheet(item: $replaying) { record in
            ReplayView(record: record, names: analysis.names)
        }
    }

    /// A phone has no room for two thousand rows, and nobody reads them there.
    /// The longest games — the hardest fought — come first, five at a time.
    private var compactList: some View {
        let sorted = analysis.games.sorted {
            longestFirst ? ($0.length, $1.index) > ($1.length, $0.index) : ($0.length, $0.index) < ($1.length, $1.index)
        }
        let shown = showsAll ? sorted : Array(sorted.prefix(5))
        return List {
            Section {
                ForEach(shown) { game in
                    Button { replaying = game } label: {
                        let down = analysis.names[game.down], across = analysis.names[game.across]
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(down) v \(across)").font(.headline)
                                Text("#\(game.index + 1) · \(game.size)×\(game.size) · \(game.winner == .blue ? down : across) won as \(game.winner.displayName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(game.length)").font(.title3.monospacedDigit().weight(.semibold))
                            Text("moves").font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if sorted.count > 5 {
                    Button(showsAll ? "Show Five" : "Show All \(sorted.count) Games") { showsAll.toggle() }
                }
            } header: {
                Picker("Order", selection: $longestFirst) {
                    Text("Longest first").tag(true)
                    Text("Shortest first").tag(false)
                }
                .pickerStyle(.segmented)
                .textCase(nil)
                .padding(.bottom, 6)
            }
        }
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $order) {
            TableColumn("#", value: \.index) { Text("\($0.index + 1)").monospacedDigit() }
                .width(min: 40, ideal: 50, max: 70)
            TableColumn("Size", value: \.size) { Text("\($0.size)×\($0.size)").monospacedDigit() }
                .width(min: 50, ideal: 60, max: 80)
            TableColumn("Down", value: \.down)
            TableColumn("Across", value: \.across)
            TableColumn("Winner", value: \.winnerName) { row in
                Text("\(row.winnerName) (\(row.colour))")
            }
            TableColumn("Moves", value: \.length) { Text("\($0.length)").monospacedDigit() }
                .width(min: 50, ideal: 60, max: 80)
        }
        .contextMenu(forSelectionType: GameRecord.ID.self) { _ in
        } primaryAction: { ids in
            if let id = ids.first { replaying = analysis.games.first { $0.index == id } }
        }
        .onChange(of: selection) { _, id in
            #if !os(macOS)
            if let id { replaying = analysis.games.first { $0.index == id } }
            #endif
        }
    }
}

/// One stored game, move by move, with the race drawn underneath.
struct ReplayView: View {
    let record: GameRecord
    let names: [String]
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step: Double = 0
    @State private var playing = false
    /// Down's chance after each move, as the judge sees it.
    @State private var chances: [Int: Double] = [:]
    @State private var judgeName: String?

    private var count: Int { Int(step.rounded()) }

    /// Games from Play have no seed and no place in an experiment: those parts
    /// are left out rather than shown as "Game 1 · seed 0000…".
    private var subtitle: String {
        var parts = ["\(record.size)×\(record.size)", "\(names[record.winner == .blue ? record.down : record.across]) won as \(record.winner.displayName)"]
        if record.seed != 0 {
            parts.insert("Game \(record.index + 1)", at: 0)
            parts.append("seed \(String(format: "%016llX", record.seed))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationStack {
            // Scrolls: board, slider, two charts and commentary are more than
            // an iPhone screen holds.
            ScrollView {
            VStack(spacing: 12) {
                BoardCanvas(
                    state: record.position(after: count),
                    theme: model.settings.theme,
                    style: model.settings.boardStyle,
                    cap: model.settings.bridgeCap,
                    guideDots: true,
                    // Scrubbing, the halo marks the move just played; on the
                    // final position the game is over and nothing is "last".
                    highlightsLastMove: count < record.length
                )
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 520)

                HStack {
                    Button { playing.toggle() } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    Slider(value: $step, in: 0...Double(max(record.length, 1)), step: 1)
                    Text("\(count)/\(record.length)").monospacedDigit().frame(minWidth: 56, alignment: .trailing)
                }
                .frame(maxWidth: 520)

                winChart.frame(maxWidth: 520)
                raceChart.frame(maxWidth: 520)

                GameCommentaryView(record: record, names: names)
                    .frame(maxWidth: 520, alignment: .leading)
            }
            .padding()
            .frame(maxWidth: .infinity)
            }
            .navigationTitle("\(names[record.down]) v \(names[record.across])")
            .replayTitleDisplay()
            .platformSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: playing) {
                while playing, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(350))
                    if count >= record.length { playing = false; break }
                    step += 1
                }
            }
            .onAppear { step = Double(record.length) }
            .task { await estimate() }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 760)
        #endif
    }

    /// Who was winning after each move, by a trained agent's judgement,
    /// following the slider.
    @ViewBuilder
    private var winChart: some View {
        if chances.isEmpty {
            if judgeName == nil, model.agents.agents.isEmpty {
                Label("Train an agent to see who was winning after each move.", systemImage: "brain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView().frame(height: 120)
            }
        } else {
            let theme = model.settings.theme
            let now = chances[count] ?? 0.5
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Win chance").font(.caption.weight(.semibold))
                    Spacer()
                    Text(verbatim: "\(Player.blue.displayName) \(Int((now * 100).rounded()))% · \(Player.red.displayName) \(Int(((1 - now) * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Chart {
                    ForEach(chances.sorted { $0.key < $1.key }, id: \.key) { move, down in
                        // Two areas, one per side: a single series takes one
                        // colour, which painted Across's lead in Down's.
                        AreaMark(x: .value("Move", move), yStart: .value("Even", 0.5), yEnd: .value("Down", max(down, 0.5)), series: .value("Side", "Down"))
                            .foregroundStyle(theme.color(for: .blue).opacity(0.3))
                        AreaMark(x: .value("Move", move), yStart: .value("Even", 0.5), yEnd: .value("Down", min(down, 0.5)), series: .value("Side", "Across"))
                            .foregroundStyle(theme.color(for: .red).opacity(0.3))
                        LineMark(x: .value("Move", move), y: .value("Down", down))
                            .foregroundStyle(.secondary)
                    }
                    RuleMark(x: .value("Now", count)).foregroundStyle(.primary)
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            switch value.as(Double.self) {
                            case 1?: Text(Player.blue.displayName)
                            case 0?: Text(Player.red.displayName)
                            default: Text("even")
                            }
                        }
                    }
                }
                .frame(height: 110)
                if let judgeName {
                    Text("Judged by \(judgeName)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func estimate() async {
        guard let judge = model.agents.agents.last, let network = model.agents.network(for: judge) else { return }
        judgeName = judge.name
        let record = self.record
        let computed = await Task.detached(priority: .utility) {
            let board = Board(size: record.size)
            let moves = record.moves.map { board.move(at: Int($0)) }
            return WinEstimate.history(moves: moves, board: board, counts: Array(0...moves.count), network: network)
        }.value
        chances = computed
    }

    /// Moves each side still needed after every move — the race as it went.
    private var raceChart: some View {
        let race = RaceHistory.compute(record)
        return Chart {
            ForEach(race) { point in
                LineMark(x: .value("Move", point.move), y: .value("To go", point.remaining))
                    .foregroundStyle(by: .value("Side", point.side.displayName))
            }
            RuleMark(x: .value("Now", count)).foregroundStyle(.secondary)
        }
        .chartForegroundStyleScale([
            Player.blue.displayName: model.settings.theme.color(for: .blue),
            Player.red.displayName: model.settings.theme.color(for: .red)
        ])
        .chartYAxisLabel("Moves to go")
        .frame(height: 140)
    }
}

/// The shortest route each side had left after every move of a game.
enum RaceHistory {
    struct Point: Identifiable, Hashable {
        var id: String { "\(side.rawValue)-\(move)" }
        let move: Int
        let side: Player
        let remaining: Int
    }

    static func compute(_ record: GameRecord) -> [Point] {
        var state = GameState(size: record.size)
        var points: [Point] = []
        for move in 0...record.length {
            if move > 0 { state.apply(state.board.move(at: Int(record.moves[move - 1]))) }
            for side in Player.allCases {
                if let remaining = ShortestPath.movesToWin(in: state, for: side) {
                    points.append(Point(move: move, side: side, remaining: remaining))
                }
            }
        }
        return points
    }

    /// A change in the race: moves each side still needed before and after one move.
    struct Turn: Hashable {
        let move: Int
        let downBefore: Int?, acrossBefore: Int?
        let downAfter: Int?, acrossAfter: Int?

        /// How far the race moved in Down's favour. A side with no route left
        /// counts as far behind, but not infinitely.
        var swing: Int {
            func gap(_ down: Int?, _ across: Int?) -> Int { (across ?? 50) - (down ?? 50) }
            return gap(downAfter, acrossAfter) - gap(downBefore, acrossBefore)
        }
    }

    /// Where the race turned most, in move order. The winning move itself is
    /// left out: every game ends with one, and it says nothing.
    static func turningPoints(_ record: GameRecord, limit: Int = 3) -> [Turn] {
        let points = compute(record)
        func remaining(_ side: Player, at move: Int) -> Int? {
            points.first { $0.move == move && $0.side == side }?.remaining
        }
        guard record.length > 1 else { return [] }
        let turns = (1..<record.length).map { move in
            Turn(move: move,
                 downBefore: remaining(.blue, at: move - 1), acrossBefore: remaining(.red, at: move - 1),
                 downAfter: remaining(.blue, at: move), acrossAfter: remaining(.red, at: move))
        }
        return turns
            .filter { $0.swing != 0 }
            .sorted { abs($0.swing) > abs($1.swing) }
            .prefix(limit)
            .sorted { $0.move < $1.move }
    }
}

private extension View {
    @ViewBuilder
    func replayTitleDisplay() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
