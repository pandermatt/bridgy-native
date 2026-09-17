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
                    Label(
                        configuration.isWatchOnly ? "Watch" : "Start",
                        systemImage: "play.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    // Runs between the two players' colours: the game is about
                    // two sides meeting, and the button may as well say so.
                    //
                    // Not `.glassProminent` with a gradient tint — `Glass.tint`
                    // only takes a flat colour, so the gradient is resolved away
                    // to one. Painting the gradient and putting clear glass over
                    // it keeps the material's press behaviour and the colour both.
                    .background(startGradient, in: .capsule)
                    .interactiveGlass(in: .capsule)
                    // All of this has to live inside the label. `.plain` hit-tests
                    // the label's drawn content, and a Label is glyphs with
                    // transparent space around them — decorating the Button from
                    // outside left most of the capsule dead to clicks.
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
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

    private var startGradient: LinearGradient {
        LinearGradient(
            colors: [
                model.settings.theme.color(for: .blue),
                model.settings.theme.color(for: .red)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
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
        let colour = model.settings.theme.color(for: player)
        return Section {
            // A Menu rather than a Picker, only so the *selected* value can be
            // laid out here. A menu Picker renders its selection itself from the
            // plain title: a Label, an HStack(spacing:) and even a symbol
            // interpolated into the Text all get collapsed or dropped, which is
            // why the icon sat welded to the word.
            LabeledContent {
                Menu {
                    Picker("Played by", selection: binding(for: player)) {
                        Text("You").tag(Seat.human)
                        ForEach(Difficulty.allCases) { level in
                            Text(level.displayName).tag(Seat.computer(level))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    seatValue(binding(for: player).wrappedValue)
                }
            } label: {
                Label {
                    Text("Played by")
                } icon: {
                    Image(systemName: player.symbolName).foregroundStyle(colour)
                }
            }

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
            HStack(spacing: 7) {
                Circle()
                    .fill(colour)
                    .frame(width: 10, height: 10)
                Text(player.displayName)
                Spacer()
                Text(player.goalDescription).textCase(nil)
            }
        }
    }

    /// The chosen seat, as the row shows it: symbol, a real gap, the name, and
    /// the up/down chevron a picker would have drawn.
    private func seatValue(_ seat: Seat) -> some View {
        HStack(spacing: 7) {
            Image(systemName: seat.symbolName)
            Text(seat.displayName)
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
                .foregroundStyle(.secondary)
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
