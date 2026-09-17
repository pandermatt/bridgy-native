// Snapshots macOS grouped-Form layouts without a screen.
//
//   swiftc Tools/RenderForms.swift -o /tmp/renderforms && /tmp/renderforms /tmp/out
//
// Why this exists: a grouped `Form` on macOS drops the last `.plain` Button of a
// section outside the section's card and draws it in secondary grey, as though
// it were footer text. That is what made the last theme, Ember, look detached in
// Settings. It reproduces only inside a NavigationStack with enough content to
// scroll, which is why a small snippet never showed it.
//
// Two things to know before reaching for this again:
//
//   * `ImageRenderer` is no use here. It renders plain SwiftUI fine, but any
//     List or Form comes back as SwiftUI's "cannot render" placeholder, because
//     they are AppKit scroll containers that need a real view hierarchy.
//     An offscreen NSWindow plus NSHostingView.cacheDisplay does work, and needs
//     no screen-recording permission — the app draws itself into a bitmap.
//   * Compile it. Under `swift -e` the interpreter fails to materialize
//     `View.tag(_:includeOptional:)`, so anything with a Picker dies at JIT time.
//
// `before` reproduces the bug, `after` is the shipped shape. Keeping both means
// the next person can check the assumption rather than trust this comment.

import AppKit
import SwiftUI

struct SettingsShape: View {
    /// True reproduces the bug: rows as `.plain` buttons.
    var useButtonRows: Bool
    /// The preview section also happens to hide it, by moving Theme off the top.
    /// That is luck, not a fix — the form scrolls.
    var showPreview: Bool

    private let themes = ["Classic", "Contrast", "Ocean", "Sunset", "Orchid", "Ember"]
    private let styles = ["Classic", "Joined", "Lines", "Bold", "Bolder", "Neon"]

    var body: some View {
        NavigationStack {
            Form {
                if showPreview {
                    Section {
                        Color.gray.opacity(0.2).frame(height: 120)
                    } header: {
                        Text("Preview")
                    } footer: {
                        Text("The colours, style and ends below, on a sample position.")
                    }
                }

                Section {
                    ForEach(themes, id: \.self) { name in
                        row(selected: name == "Contrast") {
                            HStack(spacing: 10) {
                                HStack(spacing: 5) {
                                    Circle().fill(.blue).frame(width: 18, height: 18)
                                    Circle().fill(.orange).frame(width: 18, height: 18)
                                }
                                Text(name)
                            }
                        }
                    }
                } header: {
                    Text("Theme")
                } footer: {
                    Text("Contrast, Ocean and Ember stay distinguishable with colour vision deficiency.")
                }

                Section {
                    ForEach(styles, id: \.self) { name in
                        row(selected: name == "Classic") {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                Text("A description of \(name).")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Board style")
                } footer: {
                    Text("Also the style a finished game is shared in.")
                }

                Section("Board") {
                    Toggle("Show moves needed", isOn: .constant(false))
                    Toggle("Highlight the winning path", isOn: .constant(true))
                }
                Section("Feedback") {
                    Toggle("Sound", isOn: .constant(true))
                    Toggle("Haptics", isOn: .constant(true))
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
    }

    @ViewBuilder
    private func row<Content: View>(
        selected: Bool,
        @ViewBuilder label: () -> Content
    ) -> some View {
        let content = HStack {
            label()
            Spacer(minLength: 12)
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(.rect)

        if useButtonRows {
            Button {} label: { content }.buttonStyle(.plain)
        } else {
            content.onTapGesture {}
        }
    }
}

/// The Tournament setup section. It used to be a bare `List` with no style at
/// all, which on macOS meant no grouped card, steppers stretched edge to edge
/// with their arrows pinned right, and a small default push button.
struct TournamentShape: View {
    var styled: Bool
    @State private var smallest = 4
    @State private var largest = 6
    @State private var games = 3

    var body: some View {
        NavigationStack {
            Group {
                if styled {
                    Form { sections }.formStyle(.grouped)
                } else {
                    List { sections }
                }
            }
            .navigationTitle("Tournament")
        }
    }

    @ViewBuilder private var sections: some View {
        Section {
            if styled {
                Stepper("Smallest board: \(smallest)", value: $smallest, in: 2...12)
                Stepper("Largest board: \(largest)", value: $largest, in: 2...12)
                Stepper("Games per colour: \(games)", value: $games, in: 1...50)
                Button {} label: { Text("Run 270 Games").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Stepper(value: $smallest, in: 2...12) {
                    LabeledContent("Smallest board", value: "\(smallest)")
                }
                Stepper(value: $largest, in: 2...12) {
                    LabeledContent("Largest board", value: "\(largest)")
                }
                Stepper(value: $games, in: 1...50) {
                    LabeledContent("Games per colour", value: "\(games)")
                }
                Button("Run 270 Games") {}
            }
        } header: {
            Text("Setup")
        } footer: {
            Text("Every difficulty plays every other, in both colours, at each board size.")
        }
        Section {
            Color.gray.opacity(0.15).frame(height: 180)
        } header: {
            Text("Ratings")
        } footer: {
            Text("Elo, updated after every game.")
        }
    }
}

@MainActor
func snapshot<V: View>(_ view: V, named name: String, to directory: URL, size: NSSize) {
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.frame = NSRect(origin: .zero, size: size)
    window.contentView = host
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    // Let SwiftUI settle before the bitmap is taken.
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))

    guard let representation = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        print("\(name): no bitmap")
        return
    }
    host.cacheDisplay(in: host.bounds, to: representation)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        print("\(name): no png")
        return
    }
    try? data.write(to: directory.appendingPathComponent("\(name).png"))
    print("\(name): \(representation.pixelsWide)x\(representation.pixelsHigh)")
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : NSTemporaryDirectory())
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.prohibited)
    let size = NSSize(width: 1000, height: 620)
    snapshot(
        SettingsShape(useButtonRows: true, showPreview: false),
        named: "before", to: outputDirectory, size: size
    )
    snapshot(
        SettingsShape(useButtonRows: false, showPreview: true),
        named: "after", to: outputDirectory, size: size
    )
    snapshot(
        TournamentShape(styled: false),
        named: "tournament-before", to: outputDirectory, size: size
    )
    snapshot(
        TournamentShape(styled: true),
        named: "tournament-after", to: outputDirectory, size: size
    )
}
