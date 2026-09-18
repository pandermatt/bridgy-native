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
    @State private var judgeID: UUID?
    /// Down's chance of winning after each number of moves, as the judge sees it.
    @State private var estimates: [Int: Double] = [:]
    /// What `estimates` were computed for, so an undo, a restart or another
    /// judge throws them away rather than mixing games.
    @State private var estimatedMoves: [Move] = []
    @State private var estimatedBy: UUID?

    private var state: GameState { session.state }
    private var judge: SavedAgent? {
        model.agents.agents.first { $0.id == judgeID } ?? model.agents.agents.last
    }

    var body: some View {
        Form {
            raceSection
            estimateSection
            movesSection
        }
        .formStyle(.grouped)
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
            if let judge {
                if model.agents.agents.count > 1 {
                    Picker("Judge", selection: Binding(get: { judge.id }, set: { judgeID = $0 })) {
                        ForEach(model.agents.agents) { Text($0.name).tag($0.id) }
                    }
                }
                if let current = estimates[reviewIndex ?? state.moveCount] {
                    estimateBar(current)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if estimates.count > 1 {
                    estimateChart
                }
                if judge.parameters.boardSize != state.board.size {
                    Text("\(judge.name) trained on \(judge.parameters.boardSize)×\(judge.parameters.boardSize), so read this loosely on a \(state.board.size)×\(state.board.size) board.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Train an agent in Agents and it will judge every position here.")
                    .font(.callout).foregroundStyle(.secondary)
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
            ForEach(estimates.sorted { $0.key < $1.key }, id: \.key) { move, down in
                AreaMark(x: .value("Move", move), yStart: .value("Even", 0.5), yEnd: .value("Down", down))
                    .foregroundStyle(model.settings.theme.color(for: down >= 0.5 ? .blue : .red).opacity(0.35))
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
                        Text(move.description).monospaced()
                        Spacer()
                        if let down = estimates[index + 1] {
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
                Text("Click a move to see the board as it was then.")
            }
        }
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
        guard let judge, let network = model.agents.network(for: judge) else {
            estimates = [:]
            return
        }
        let moves = state.moves
        let board = state.board
        if estimatedBy != judge.id || !moves.starts(with: estimatedMoves) {
            estimates = [:]
            estimatedBy = judge.id
        }
        estimatedMoves = moves
        let wanted = board.size <= 15 ? Array(0...moves.count) : [moves.count]
        let missing = wanted.filter { estimates[$0] == nil }
        guard !missing.isEmpty else { return }
        let computed = await Task.detached(priority: .utility) {
            var results: [Int: Double] = [:]
            var position = GameState(board: board)
            var played = 0
            for count in missing.sorted() {
                if Task.isCancelled { break }
                while played < count { position.apply(moves[played]); played += 1 }
                results[count] = Self.downChance(position, network: network)
            }
            return results
        }.value
        estimates.merge(computed) { _, new in new }
    }

    nonisolated private static func downChance(_ state: GameState, network: NeuralNetwork) -> Double {
        if let winner = state.winner { return winner == .blue ? 1 : 0 }
        let value = Double(network.judge(state).value)
        let mover = (value + 1) / 2
        return state.current == .blue ? mover : 1 - mover
    }
}
