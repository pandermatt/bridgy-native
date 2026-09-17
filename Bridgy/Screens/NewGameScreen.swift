import BridgyEngine
import SwiftUI

/// Choose the board size and who plays each colour.
struct NewGameScreen: View {
    @Environment(AppModel.self) private var model
    @State private var configuration: GameConfiguration
    var watchOnly = false
    var onStart: (GameConfiguration) -> Void

    init(configuration: GameConfiguration, watchOnly: Bool = false, onStart: @escaping (GameConfiguration) -> Void) {
        var initial = configuration
        if watchOnly {
            if !initial.blue.isComputer { initial.blue = .computer(.hard) }
            if !initial.red.isComputer { initial.red = .computer(.expert) }
        }
        _configuration = State(initialValue: initial)
        self.watchOnly = watchOnly
        self.onStart = onStart
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                sizeCard
                seatCard(for: .blue)
                seatCard(for: .red)
                startButton
            }
            .padding(20)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background { BackdropView(backdrop: model.settings.backdrop) }
        .navigationTitle(watchOnly ? "Watch" : "New Game")
    }

    private var sizeCard: some View {
        card {
            HStack {
                Label("Board size", systemImage: "square.grid.3x3")
                    .font(.headline)
                Spacer()
                Text("\(configuration.size)×\(configuration.size)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(configuration.size) },
                    set: { configuration.size = Int($0.rounded()) }
                ),
                in: Double(Board.minimumSize)...Double(Board.maximumSize),
                step: 1
            )
            Text(sizeAdvice)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sizeAdvice: String {
        switch configuration.size {
        case ..<4: return "Tiny. Over in a handful of moves."
        case 4...8: return "A comfortable game."
        case 9...16: return "Long, and the computer takes longer to think."
        default: return "Enormous. Pinch to zoom the board."
        }
    }

    private func seatCard(for player: Player) -> some View {
        card {
            HStack {
                Label {
                    Text(player.displayName)
                } icon: {
                    Image(systemName: player.symbolName)
                        .foregroundStyle(model.settings.colorway.color(for: player))
                }
                .font(.headline)
                Spacer()
                Text(player.goalDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Played by", selection: binding(for: player)) {
                if !watchOnly {
                    Label("You", systemImage: "person").tag(Seat.human)
                }
                ForEach(Difficulty.allCases) { level in
                    Label(level.displayName, systemImage: level.symbolName)
                        .tag(Seat.computer(level))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if let level = binding(for: player).wrappedValue.difficulty {
                Text(level.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let caveat = level.caveat {
                    Label(caveat, systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func binding(for player: Player) -> Binding<Seat> {
        player == .blue
            ? Binding(get: { configuration.blue }, set: { configuration.blue = $0 })
            : Binding(get: { configuration.red }, set: { configuration.red = $0 })
    }

    private var startButton: some View {
        Button {
            onStart(configuration)
        } label: {
            Label(watchOnly ? "Watch" : "Start", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.glassProminent)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}
