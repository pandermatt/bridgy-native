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
    var onPlayAgain: () -> Void
    var onChangeSetup: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?

    /// Every one of these is local to this sheet on purpose. Dressing a finished
    /// game up for sharing is about the picture, not about how the next game will
    /// be drawn — those live in the game's own toolbar and in Settings. They are
    /// seeded from the stored settings and never written back.
    @State private var style: BoardStyle
    @State private var theme: BoardTheme
    @State private var cap: BridgeCap
    @State private var dimsLoser = true
    @State private var highlightsPath: Bool

    /// Computed once for the whole sheet: the board redraws on every control.
    @State private var path: Set<Int> = []

    init(
        state: GameState,
        configuration: GameConfiguration,
        theme: BoardTheme,
        cap: BridgeCap,
        initialStyle: BoardStyle,
        highlightsWinningPath: Bool,
        onPlayAgain: @escaping () -> Void,
        onChangeSetup: @escaping () -> Void
    ) {
        self.state = state
        self.configuration = configuration
        self.onPlayAgain = onPlayAgain
        self.onChangeSetup = onChangeSetup
        _style = State(initialValue: initialStyle)
        _theme = State(initialValue: theme)
        _cap = State(initialValue: cap)
        _highlightsPath = State(initialValue: highlightsWinningPath)
    }

    private var shownPath: Set<Int>? { highlightsPath ? path : nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    board
                    pictureControls
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
        .task { path = Set(WinningPath.forWinner(of: state)) }
        .task(id: picture) { shareURL = renderShareImage() }
    }

    /// Everything the rendered picture depends on, so one `.task` covers them all.
    private var picture: PictureSettings {
        PictureSettings(style: style, theme: theme, cap: cap, dimsLoser: dimsLoser, path: shownPath)
    }

    struct PictureSettings: Equatable {
        var style: BoardStyle
        var theme: BoardTheme
        var cap: BridgeCap
        var dimsLoser: Bool
        var path: Set<Int>?
    }

    private var board: some View {
        BoardCanvas(
            state: state,
            theme: theme,
            style: style,
            cap: cap,
            dimsLoser: dimsLoser,
            winningPath: shownPath,
            highlightsLastMove: false
        )
            .aspectRatio(1, contentMode: .fit)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(style.prefersDarkGround ? AnyShapeStyle(Color.black) : AnyShapeStyle(.background.secondary))
            }
    }

    private var pictureControls: some View {
        VStack(spacing: 10) {
            LabeledContent("Style") {
                Picker("Style", selection: $style) {
                    ForEach(BoardStyle.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            LabeledContent("Colours") {
                Picker("Colours", selection: $theme) {
                    ForEach(BoardTheme.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            LabeledContent("Ends") {
                Picker("Ends", selection: $cap) {
                    ForEach(BridgeCap.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            Toggle("Dim the loser", isOn: $dimsLoser)
            Toggle("Highlight the winning path", isOn: $highlightsPath)
                .disabled(path.isEmpty)

            Text(style.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
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
                dimsLoser: dimsLoser,
                winningPath: shownPath,
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
    let dimsLoser: Bool
    let winningPath: Set<Int>?
    let caption: String

    var body: some View {
        VStack(spacing: 18) {
            BoardCanvas(
                state: state,
                theme: theme,
                style: style,
                cap: cap,
                dimsLoser: dimsLoser,
                winningPath: winningPath,
                highlightsLastMove: false
            )
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
