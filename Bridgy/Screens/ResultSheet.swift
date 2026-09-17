import BridgyEngine
import SwiftUI

/// Shown when a game ends: the finished board, a style to draw it in, and a way
/// to share it.
///
/// This replaced an `.alert`, which cannot host a `ShareLink` — and a finished
/// board is worth more than a two-line dialog anyway.
struct ResultSheet: View {
    let state: GameState
    let configuration: GameConfiguration
    let theme: BoardTheme
    let cap: BridgeCap
    var onPlayAgain: () -> Void
    var onChangeSetup: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?

    /// Local to this sheet on purpose: picking a style here is about the picture
    /// being shared, not about how the next game will be drawn. The board style
    /// proper is changed from the game's own toolbar or from Settings.
    @State private var style: BoardStyle

    init(
        state: GameState,
        configuration: GameConfiguration,
        theme: BoardTheme,
        cap: BridgeCap,
        initialStyle: BoardStyle,
        onPlayAgain: @escaping () -> Void,
        onChangeSetup: @escaping () -> Void
    ) {
        self.state = state
        self.configuration = configuration
        self.theme = theme
        self.cap = cap
        self.onPlayAgain = onPlayAgain
        self.onChangeSetup = onChangeSetup
        _style = State(initialValue: initialStyle)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    board
                    stylePicker
                    actions
                }
                .padding()
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: style) { shareURL = renderShareImage() }
    }

    private var board: some View {
        BoardCanvas(state: state, theme: theme, style: style, cap: cap, highlightsLastMove: false)
            .aspectRatio(1, contentMode: .fit)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(style.prefersDarkGround ? AnyShapeStyle(Color.black) : AnyShapeStyle(.background.secondary))
            }
    }

    private var stylePicker: some View {
        VStack(spacing: 6) {
            Picker("Picture style", selection: $style) {
                ForEach(BoardStyle.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            Text(style.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let shareURL {
                ShareLink(item: shareURL) {
                    Label("Share Image", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            Button {
                dismiss()
                onPlayAgain()
            } label: {
                Label("Play Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            Button {
                dismiss()
                onChangeSetup()
            } label: {
                Label("Change Setup", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    private var title: String {
        guard let winner = state.winner else { return "Game Over" }
        if configuration.soloHumanPlayer == winner { return "You Win" }
        return "\(winner.displayName) Wins"
    }

    private var subtitle: String {
        "\(state.moveCount) moves · \(state.board.size)×\(state.board.size)"
    }

    /// Renders the board to a PNG on disk. A file URL rather than an in-memory
    /// image so the share sheet gets a sensible filename to hand on.
    @MainActor
    private func renderShareImage() -> URL? {
        let renderer = ImageRenderer(
            content: ShareableBoard(
                state: state,
                theme: theme,
                style: style,
                cap: cap,
                caption: "\(title) · \(subtitle)"
            )
        )
        renderer.scale = 3
        renderer.isOpaque = true

        guard let data = renderer.pngData else { return nil }
        let url = URL.temporaryDirectory.appendingPathComponent("bridgy-\(style.rawValue).png")
        try? data.write(to: url, options: .atomic)
        return url
    }
}

/// The board as it appears in a shared image: fixed size, its own ground, one
/// restrained caption.
struct ShareableBoard: View {
    let state: GameState
    let theme: BoardTheme
    let style: BoardStyle
    let cap: BridgeCap
    let caption: String

    var body: some View {
        VStack(spacing: 18) {
            BoardCanvas(state: state, theme: theme, style: style, cap: cap, highlightsLastMove: false)
                .frame(width: 440, height: 440)
            Text(caption)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(style.prefersDarkGround ? .white : .primary)
                .opacity(0.75)
        }
        .padding(32)
        .frame(width: 504, height: 560)
        .background(style.prefersDarkGround ? Color.black : Color(white: 0.98))
        .environment(\.colorScheme, style.prefersDarkGround ? .dark : .light)
    }
}

extension ImageRenderer {
    /// PNG bytes, on whichever platform we are.
    @MainActor
    var pngData: Data? {
        #if os(iOS)
        return uiImage?.pngData()
        #else
        guard let cgImage else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .png, properties: [:])
        #endif
    }
}
