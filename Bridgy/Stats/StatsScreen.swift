import BridgyEngine
import Charts
import GameKit
import SwiftUI

/// How you play: overall, against each opponent, by board size, and the games
/// worth remembering.
struct StatsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var replaying: PlayedGame?

    var body: some View {
        let stats = PlayerStats(history: model.history.games)
        Group {
            if stats.games.isEmpty {
                ContentUnavailableView(
                    "No Games Yet",
                    systemImage: "chart.bar",
                    description: Text("Finish a game against the computer or one of your agents and your record starts here.")
                )
            } else {
                Form {
                    overview(stats)
                    opponents(stats)
                    if stats.bySize.count > 1 { sizes(stats) }
                    records(stats)
                    if model.settings.puzzlesTried > 0 {
                        Section("Puzzles") {
                            LabeledContent("Solved", value: "\(model.settings.puzzlesSolved) of \(model.settings.puzzlesTried)")
                        }
                    }
                    allGames(stats)
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("Your Stats")
        .toolbar {
            if GameCenter.isSignedIn {
                ToolbarItem(placement: .primaryAction) {
                    Button { GKAccessPoint.shared.trigger(state: .dashboard) {} } label: {
                        Label("Game Center", systemImage: "gamecontroller")
                    }
                }
            }
        }
        .sheet(item: $replaying) { game in
            ReplayView(record: game.record, names: game.names)
        }
    }

    private func percent(_ record: Record) -> String {
        record.isEmpty ? "–" : "\(Int((record.rate * 100).rounded()))%"
    }

    private func overview(_ stats: PlayerStats) -> some View {
        Section {
            HStack(spacing: 0) {
                tile("\(stats.overall.games)", "games")
                Divider()
                tile("\(stats.overall.wins)", "won")
                Divider()
                tile(percent(stats.overall), "win rate")
            }
            .frame(height: 64)
            LabeledContent("As Down (first)") {
                Text("\(stats.asDown.wins) of \(stats.asDown.games) · \(percent(stats.asDown))").monospacedDigit()
            }
            LabeledContent("As Across (second)") {
                Text("\(stats.asAcross.wins) of \(stats.asAcross.games) · \(percent(stats.asAcross))").monospacedDigit()
            }
        } footer: {
            if stats.overall.games >= 5 {
                Text("Your true win rate is likely between \(stats.overall.interval.description()), given \(stats.overall.games) games.")
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.semibold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func opponents(_ stats: PlayerStats) -> some View {
        Section("Against") {
            ForEach(stats.opponents) { line in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(line.opponent, systemImage: line.symbol)
                        Spacer()
                        Text("\(line.overall.wins)–\(line.overall.games - line.overall.wins)")
                            .font(.headline.monospacedDigit())
                    }
                    ProgressView(value: line.overall.rate)
                        .tint(line.overall.rate >= 0.5 ? .green : .orange)
                    Text("As Down \(percent(line.asDown)) · As Across \(percent(line.asAcross))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func sizes(_ stats: PlayerStats) -> some View {
        Section("By board size") {
            Chart(stats.bySize) { point in
                BarMark(x: .value("Size", "\(point.size)×\(point.size)"), y: .value("Win rate", point.record.rate))
                    .foregroundStyle(.tint)
                    .annotation(position: .top) {
                        Text("\(point.record.games)").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartYScale(domain: 0...1)
            .chartYAxis { AxisMarks(format: Decimal.FormatStyle.Percent.percent.precision(.fractionLength(0))) }
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private func records(_ stats: PlayerStats) -> some View {
        Section("Your records") {
            if let game = stats.fastestWin {
                recordRow("Fastest win", "\(game.record.length) moves on \(game.record.size)×\(game.record.size)", game)
            }
            if let game = stats.biggestWin {
                recordRow("Biggest board won", "\(game.record.size)×\(game.record.size) against \(opponentName(game))", game)
            }
            ForEach(stats.firstWins, id: \.level) { entry in
                LabeledContent {
                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                } label: {
                    Label("First win against \(entry.level.displayName)", systemImage: entry.level.symbolName)
                }
            }
            if stats.fastestWin == nil {
                Text("No wins yet — they'll show up here.").foregroundStyle(.secondary)
            }
        }
    }

    private func recordRow(_ title: String, _ detail: String, _ game: PlayedGame) -> some View {
        Button { replaying = game } label: {
            LabeledContent(title) { Text(detail) }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func opponentName(_ game: PlayedGame) -> String {
        guard let me = game.configuration.soloHumanPlayer else { return "" }
        return game.configuration.seat(for: me.opponent).displayName
    }

    private func allGames(_ stats: PlayerStats) -> some View {
        Section("All games") {
            ForEach(stats.games) { game in
                PlayedGameRow(game: game) { replaying = game }
            }
        }
    }
}

/// One finished game from Play, tap to replay.
struct PlayedGameRow: View {
    let game: PlayedGame
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.title).font(.headline)
                    Text("\(game.record.size)×\(game.record.size) · \(game.winnerName) won as \(game.record.winner.displayName) · \(game.date.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(game.record.length)").font(.title3.monospacedDigit().weight(.semibold))
                Text("moves").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
