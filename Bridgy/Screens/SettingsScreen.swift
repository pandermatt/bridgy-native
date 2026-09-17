import BridgyEngine
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                ForEach(BoardTheme.allCases) { theme in
                    choiceRow(
                        isSelected: settings.theme == theme,
                        action: { settings.theme = theme }
                    ) {
                        HStack(spacing: 10) {
                            dots(for: theme)
                            Text(theme.displayName)
                        }
                    }
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("Contrast, Ocean and Ember stay distinguishable with colour vision deficiency.")
            }

            Section {
                ForEach(BoardStyle.allCases) { style in
                    choiceRow(
                        isSelected: settings.boardStyle == style,
                        action: { settings.boardStyle = style }
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.displayName)
                            Text(style.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Picker("Bridge ends", selection: $settings.bridgeCap) {
                    ForEach(BridgeCap.allCases) { cap in
                        Text(cap.displayName).tag(cap)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Board style")
            } footer: {
                Text("Also the style a finished game is shared in.")
            }

            Section("Board") {
                Toggle("Show moves needed", isOn: $settings.showHints)
            }

            Section("Feedback") {
                Toggle("Sound", isOn: $settings.soundEnabled)
                Toggle("Haptics", isOn: $settings.hapticsEnabled)
            }

            Section("Watching two computers") {
                WatchPaceControls(pace: $settings.watchPace)
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

    /// A list row that behaves like a picker option, so each choice can show what
    /// it actually looks like rather than describing it.
    private func choiceRow<Content: View>(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Content
    ) -> some View {
        Button(action: action) {
            HStack {
                label()
                Spacer(minLength: 12)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func dots(for theme: BoardTheme) -> some View {
        HStack(spacing: 5) {
            ForEach(Player.allCases, id: \.self) { player in
                Circle()
                    .fill(theme.color(for: player))
                    .frame(width: 18, height: 18)
            }
        }
        .accessibilityHidden(true)
    }
}
