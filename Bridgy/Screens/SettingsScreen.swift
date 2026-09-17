import BridgyEngine
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Backdrop") {
                Picker("Gradient", selection: $settings.backdrop) {
                    ForEach(Backdrop.allCases) { backdrop in
                        Text(backdrop.displayName).tag(backdrop)
                    }
                }
                swatches(selection: $settings.backdrop)
            }

            Section("Colours") {
                Picker("Players", selection: $settings.colorway) {
                    ForEach(Colorway.allCases) { colorway in
                        Text(colorway.displayName).tag(colorway)
                    }
                }
                .pickerStyle(.segmented)
                HStack(spacing: 14) {
                    ForEach(Player.allCases, id: \.self) { player in
                        Label {
                            Text(player.displayName)
                        } icon: {
                            Circle()
                                .fill(settings.colorway.color(for: player))
                                .frame(width: 14, height: 14)
                        }
                        .font(.caption)
                    }
                }
                Text(settings.colorway.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Board") {
                Toggle("Show dots", isOn: $settings.showDots)
                Toggle("Thick connections", isOn: $settings.boldLines)
                Toggle("Show moves needed", isOn: $settings.showHints)
            }

            Section("Feedback") {
                Toggle("Sound", isOn: $settings.soundEnabled)
                Toggle("Haptics", isOn: $settings.hapticsEnabled)
            }

            Section {
                Picker("Speed", selection: $settings.watchSpeed) {
                    ForEach(WatchSpeed.allCases) { speed in
                        Label(speed.displayName, systemImage: speed.symbolName).tag(speed)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Watching two computers")
            } footer: {
                Text("How long to pause between their moves.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background { BackdropView(backdrop: settings.backdrop) }
        .navigationTitle("Settings")
        .onChange(of: settings.soundEnabled) { _, enabled in
            if enabled { model.sound.prepare() }
        }
    }

    private func swatches(selection: Binding<Backdrop>) -> some View {
        HStack(spacing: 10) {
            ForEach(Backdrop.allCases) { backdrop in
                Button {
                    selection.wrappedValue = backdrop
                } label: {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(
                            colors: backdrop.swatch(for: .dark),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(height: 38)
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(
                                    selection.wrappedValue == backdrop ? Color.accentColor : .clear,
                                    lineWidth: 2.5
                                )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(backdrop.displayName)
            }
        }
        .padding(.vertical, 4)
    }
}
