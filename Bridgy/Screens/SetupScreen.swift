import BridgyEngine
import SwiftUI

/// Choose the board and who plays each colour.
///
/// There is no separate Watch screen. Putting a computer in both seats is what
/// makes a game you watch, and that is also what unlocks the full board range —
/// nobody has to tap a 35×35 board.
struct SetupScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.availableBoardSide) private var availableBoardSide
    @State private var configuration = GameConfiguration.default
    @State private var hasLoaded = false

    private var maximumSize: Int {
        BoardSizeLimit.maximumSize(for: configuration, side: availableBoardSide)
    }

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            if model.canResume {
                Section {
                    Button {
                        model.resumeGame()
                    } label: {
                        LabeledContent("Continue") {
                            Text(model.configuration.summary)
                        }
                    }
                }
            }

            Section("Board") {
                LabeledContent("Size") {
                    Text("\(configuration.size)×\(configuration.size)").monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(configuration.size) },
                        set: { configuration.size = Int($0.rounded()) }
                    ),
                    in: Double(Board.minimumSize)...Double(maximumSize),
                    step: 1
                ) {
                    Text("Board size")
                } minimumValueLabel: {
                    Text("\(Board.minimumSize)")
                } maximumValueLabel: {
                    Text("\(maximumSize)")
                }
                .labelsHidden()
                if let note = sizeNote {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            }

            seatSection(for: .blue)
            seatSection(for: .red)

            if configuration.isWatchOnly {
                Section("Speed") {
                    WatchPaceControls(pace: $settings.watchPace)
                }
            }

            Section {
                Button {
                    model.startGame(configuration)
                } label: {
                    Text(configuration.isWatchOnly ? "Watch" : "Start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Bridgy")
        .onAppear {
            if !hasLoaded {
                configuration = model.configuration
                hasLoaded = true
            }
            model.refreshResumable()
            clampSize()
        }
        .onChange(of: configuration.blue) { _, _ in clampSize() }
        .onChange(of: configuration.red) { _, _ in clampSize() }
        .onChange(of: availableBoardSide) { _, _ in clampSize() }
    }

    private var sizeNote: String? {
        if configuration.isWatchOnly {
            return "Two computers, so the whole range is available."
        }
        if maximumSize < Board.maximumSize {
            return "Larger boards get hard to tap. Set both players to a computer for the full range."
        }
        return nil
    }

    /// Keeps the board playable when a computer seat becomes a human one.
    private func clampSize() {
        configuration.size = min(max(configuration.size, Board.minimumSize), maximumSize)
    }

    private func seatSection(for player: Player) -> some View {
        Section {
            Picker(selection: binding(for: player)) {
                Label("You", systemImage: "person").tag(Seat.human)
                ForEach(Difficulty.allCases) { level in
                    Label(level.displayName, systemImage: level.symbolName)
                        .tag(Seat.computer(level))
                }
            } label: {
                Text("Played by")
            }
            .pickerStyle(.menu)

            if let level = binding(for: player).wrappedValue.difficulty {
                Text(level.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let caveat = level.caveat {
                    Text(caveat)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            HStack {
                Text(player.displayName)
                Spacer()
                Text(player.goalDescription).textCase(nil)
            }
        }
    }

    private func binding(for player: Player) -> Binding<Seat> {
        player == .blue
            ? Binding(get: { configuration.blue }, set: { configuration.blue = $0 })
            : Binding(get: { configuration.red }, set: { configuration.red = $0 })
    }
}

/// Speed slider plus the choice of whether engines may take their time.
struct WatchPaceControls: View {
    @Binding var pace: WatchPace

    var body: some View {
        LabeledContent("Pace") {
            Text(pace.rateDescription).monospacedDigit()
        }
        Slider(
            value: Binding(get: { pace.sliderPosition }, set: { pace.sliderPosition = $0 }),
            in: WatchPace.sliderRange
        ) {
            Text("Pace")
        } minimumValueLabel: {
            Image(systemName: "tortoise")
        } maximumValueLabel: {
            Image(systemName: "hare")
        }
        .labelsHidden()

        Toggle("Let engines think fully", isOn: $pace.allowsFullThinking)
        Text(
            pace.allowsFullThinking
                ? "Engines take as long as they need, so the slider only sets a minimum gap."
                : "Search is capped to keep up, so the stronger engines play weaker when sped up."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
