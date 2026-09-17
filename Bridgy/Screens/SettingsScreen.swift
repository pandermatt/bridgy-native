import BridgyEngine
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Picker("Players", selection: $settings.colorway) {
                    ForEach(Colorway.allCases) { colorway in
                        Text(colorway.displayName).tag(colorway)
                    }
                }
                .pickerStyle(.inline)
                HStack(spacing: 16) {
                    ForEach(Player.allCases, id: \.self) { player in
                        Label {
                            Text(player.displayName)
                        } icon: {
                            Circle()
                                .fill(settings.colorway.color(for: player))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
                .font(.footnote)
            } header: {
                Text("Colours")
            } footer: {
                Text(settings.colorway.detail)
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
                WatchPaceControls(pace: $settings.watchPace)
            } header: {
                Text("Watching two computers")
            }

            Section {
                NavigationLink {
                    AboutScreen()
                } label: {
                    Label("About Bridgy", systemImage: "info.circle")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: settings.soundEnabled) { _, enabled in
            if enabled { model.sound.prepare() }
        }
    }
}
