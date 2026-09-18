import BridgyEngine
import Charts
import SwiftUI

/// Beside the board on iPad and the Mac: who is ahead, how that has changed,
/// and every move so far, any of which can be stepped back to.
struct GameInspector: View {
    @Bindable var session: GameSession
    /// The move being reviewed, counted from one; nil shows the live game.
    private var reviewIndex: Int? {
        get { session.reviewIndex }
        nonmutating set { session.reviewIndex = newValue }
    }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    /// A trained agent judging instead of the search; nil is the search.
    @State private var judgeID: UUID?
    /// Down's chance of winning after each number of moves, as the judge sees it.
    @State private var estimates: [Int: Double] = [:]
    /// What `estimates` were computed for, so an undo, a restart or another
    /// judge throws them away rather than mixing games.
    @State private var estimatedMoves: [Move] = []
    @State private var estimatedBy: UUID?

    private var state: GameState { session.state }
    /// What the chart and bar show. The search's readings are smoothed; an
    /// agent's network has no move-by-move bias to take out.
    private var shown: [Int: Double] {
        judge == nil ? PositionJudge.smoothed(estimates) : estimates
    }
    private var judge: SavedAgent? {
        model.agents.agents.first { $0.id == judgeID }
    }

    var body: some View {
        Form {
            raceSection
            estimateSection
            movesSection
        }
        .formStyle(.grouped)
        .inspectorTitle()
        .toolbar {
            #if os(iOS)
            // On iPhone the inspector is a sheet, and a sheet needs a way out.
            if sizeClass == .compact {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
        .task(id: EstimateKey(moves: state.moveCount, judge: judge?.id, size: state.board.size)) {
            await refreshEstimates()
        }
    }

    // MARK: - Race

    private var raceSection: some View {
        Section("Race") {
            ForEach(Player.allCases, id: \.self) { player in
                let needed = player == .blue ? session.readout.blue : session.readout.red
                LabeledContent {
                    Text(needed.map { "\($0) to go" } ?? "cut off").monospacedDigit()
                } label: {
                    Label {
                        Text(player.displayName)
                    } icon: {
                        Image(systemName: player.symbolName)
                            .foregroundStyle(model.settings.theme.color(for: player))
                    }
                }
            }
        }
        .opacity(session.readout.isStale ? 0.6 : 1)
    }

    // MARK: - Estimate

    @ViewBuilder
    private var estimateSection: some View {
        Section {
            // Your own agents can judge too — interesting to compare with
            // the search, though a lightly trained one sits near 50%.
            if !model.agents.agents.isEmpty {
                Picker("Judge", selection: $judgeID) {
                    Text("Search").tag(UUID?.none)
                    ForEach(model.agents.agents) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if let current = shown[reviewIndex ?? state.moveCount] {
                estimateBar(current)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            if estimates.count > 1 {
                estimateChart
            }
            if let judge, judge.parameters.boardSize != state.board.size {
                Text("\(judge.name) trained on \(judge.parameters.boardSize)×\(judge.parameters.boardSize), so read this loosely on a \(state.board.size)×\(state.board.size) board.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Win estimate")
        }
    }

    private func estimateBar(_ down: Double) -> some View {
        let theme = model.settings.theme
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    theme.color(for: .blue).frame(width: proxy.size.width * down)
                    theme.color(for: .red)
                }
                .clipShape(.capsule)
            }
            .frame(height: 10)
            HStack {
                Text("\(Player.blue.displayName) \(Int((down * 100).rounded()))%")
                Spacer()
                Text("\(Player.red.displayName) \(Int(((1 - down) * 100).rounded()))%")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .animation(.smooth, value: down)
    }

    private var estimateChart: some View {
        Chart {
            ForEach(shown.sorted { $0.key < $1.key }, id: \.key) { move, down in
                // Two areas, one per side: a single series takes one
                // colour, which painted Across's lead in Down's.
                AreaMark(x: .value("Move", move), yStart: .value("Even", 0.5), yEnd: .value("Down", max(down, 0.5)), series: .value("Side", "Down"))
                    .foregroundStyle(model.settings.theme.color(for: .blue).opacity(0.3))
                AreaMark(x: .value("Move", move), yStart: .value("Even", 0.5), yEnd: .value("Down", min(down, 0.5)), series: .value("Side", "Across"))
                    .foregroundStyle(model.settings.theme.color(for: .red).opacity(0.3))
                LineMark(x: .value("Move", move), y: .value("Down", down))
                    .foregroundStyle(.secondary)
            }
            if let reviewIndex {
                RuleMark(x: .value("Move", reviewIndex)).foregroundStyle(.primary)
            }
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(values: [0, 0.5, 1]) { value in
                AxisGridLine()
                AxisValueLabel { Text(value.as(Double.self) == 0.5 ? "even" : "") }
            }
        }
        .frame(height: 90)
    }

    // MARK: - Moves

    private var movesSection: some View {
        Section {
            if reviewIndex != nil {
                Button("Back to the Game") { reviewIndex = nil }
            }
            if state.moves.isEmpty {
                Text("No moves yet.").foregroundStyle(.secondary)
            }
            ForEach(Array(state.moves.enumerated()), id: \.offset) { index, move in
                let player: Player = index % 2 == 0 ? .blue : .red
                Button {
                    reviewIndex = index + 1 == state.moveCount ? nil : index + 1
                } label: {
                    HStack {
                        Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                        Circle().fill(model.settings.theme.color(for: player)).frame(width: 8, height: 8)
                        Image(systemName: move.isVertical(for: player) ? "arrow.up.and.down" : "arrow.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(Self.place(of: move, on: state.board)).monospacedDigit()
                        Spacer()
                        if let down = shown[index + 1] {
                            Text("\(Int((down * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .listRowBackground(reviewIndex == index + 1 ? Color.accentColor.opacity(0.18) : nil)
            }
        } header: {
            Text("Moves")
        } footer: {
            if !state.moves.isEmpty {
                Text(footerText)
            }
        }
    }

    private var footerText: String {
        #if os(macOS)
        let verb = "Click"
        #else
        let verb = "Tap"
        #endif
        let estimate = estimates.isEmpty ? "" : " The percentage is Down's chance of winning after that move."
        return "\(verb) a move to see the board as it was then.\(estimate)"
    }

    /// Where a move sits, counted from the top left the way the board reads:
    /// "row 3, col 2".
    static func place(of move: Move, on board: Board) -> String {
        let centre = board.center(of: move)
        return "row \(centre.y / 2 + 1), col \(centre.x / 2 + 1)"
    }

    // MARK: - Work

    private struct EstimateKey: Hashable {
        let moves: Int
        let judge: UUID?
        let size: Int
    }

    /// Judges every position not judged yet, off the main thread. Long games on
    /// big boards judge only the latest position; a full history there would
    /// cost more than it shows.
    private func refreshEstimates() async {
        let network = judge.flatMap { model.agents.network(for: $0) }
        let moves = state.moves
        let board = state.board
        if estimatedBy != judge?.id || !moves.starts(with: estimatedMoves) {
            estimates = [:]
            estimatedBy = judge?.id
        }
        estimatedMoves = moves
        let wanted = board.size <= 15 ? Array(0...moves.count) : [moves.count]
        let missing = wanted.filter { estimates[$0] == nil }
        guard !missing.isEmpty else { return }
        let computed = await Task.detached(priority: .utility) {
            if let network {
                WinEstimate.history(moves: moves, board: board, counts: missing, network: network)
            } else {
                PositionJudge.history(moves: moves, board: board, counts: missing)
            }
        }.value
        estimates.merge(computed) { _, new in new }
    }

}

private extension View {
    /// Only where the inspector is its own sheet with its own navigation stack
    /// (iOS). Beside the board it shares the game's navigation bar, and a
    /// title here replaced "Your turn" with "Game".
    @ViewBuilder
    func inspectorTitle() -> some View {
        #if os(iOS)
        navigationTitle("Game").navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
