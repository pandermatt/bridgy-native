import BridgyEngine
import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                BoardCanvas(
                    state: BoardSample.midGame,
                    theme: settings.theme,
                    style: settings.boardStyle,
                    cap: settings.bridgeCap,
                    highlightsLastMove: false
                )
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 220)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(settings.boardStyle.prefersDarkGround
                              ? AnyShapeStyle(Color.black)
                              : AnyShapeStyle(.background.secondary))
                }
                .padding(.vertical, 6)
                .accessibilityHidden(true)
            } header: {
                Text("Preview")
            } footer: {
                Text("The colours, style and ends below, on a sample position.")
            }

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
                Toggle("Highlight the winning path", isOn: $settings.highlightsWinningPath)
            }

            Section("Feedback") {
                Toggle("Sound", isOn: $settings.soundEnabled)
                // Vision Pro has no haptic engine, so `.sensoryFeedback`
                // compiles and does nothing. A switch that cannot do anything is
                // worse than no switch.
                #if !os(visionOS)
                Toggle("Haptics", isOn: $settings.hapticsEnabled)
                #endif
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
    ///
    /// The row is a `Button` on iOS, for the press highlight, but **not** on
    /// macOS. A grouped `Form` there drops the last `.plain` button of a section
    /// outside the section's card and renders it in secondary grey, as though it
    /// were footer text — which is exactly how the last theme, Ember, was showing
    /// up. Measured offscreen with `Tools/RenderForms.swift`: identical markup
    /// with a plain row instead of a button keeps every row inside the card.
    private func choiceRow<Content: View>(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Content
    ) -> some View {
        let row = HStack {
            label()
            Spacer(minLength: 12)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(.rect)

        return Group {
            #if os(macOS)
            row.onTapGesture(perform: action)
            #else
            Button(action: action) { row }
                .buttonStyle(.plain)
            #endif
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, action)
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
