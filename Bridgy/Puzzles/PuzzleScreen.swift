import BridgyEngine
import SwiftUI

/// A random position with a forced win: find it in the moves given.
struct PuzzleScreen: View {
    @Environment(AppModel.self) private var model
    @State private var session: PuzzleSession?
    @State private var size: PuzzleSession.Size = .medium

    var body: some View {
        VStack(spacing: 16) {
            Picker("Size", selection: $size) {
                ForEach(PuzzleSession.Size.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            if let session, session.puzzle != nil {
                board(session)
                controls(session)
            } else {
                Spacer()
                ProgressView("Finding a puzzle…")
                Spacer()
            }
        }
        .padding()
        .navigationTitle(title)
        .gameScreenTitleDisplayMode()
        .platformSubtitle(subtitle)
        .task(id: size) {
            let session = PuzzleSession(size: size) { solved in model.settings.recordPuzzle(solved: solved) }
            self.session = session
            await session.next()
        }
    }

    private var title: String {
        guard let session, let you = session.you else { return "Puzzle" }
        switch session.status {
        case .solved: return "Solved!"
        case .missed: return "Not quite"
        case .showingSolution: return "The solution"
        default: return "\(you.displayName) to move · win in \(session.puzzle?.movesToWin ?? 0)"
        }
    }

    private var subtitle: String {
        guard let session, let you = session.you else { return "" }
        switch session.status {
        case .yourMove: return "\(session.remaining) move\(session.remaining == 1 ? "" : "s") left · you build \(you.goalDescription)"
        case .defending: return "They're defending…"
        case .solved: return "Forced, whatever they did."
        case .missed: return "That let them off the hook."
        case .showingSolution: return "The winning line"
        case .loading: return ""
        }
    }

    private func board(_ session: PuzzleSession) -> some View {
        GeometryReader { proxy in
            let geometry = BoardGeometry(board: session.state.board, rect: CGRect(origin: .zero, size: proxy.size))
            BoardCanvas(
                state: session.state,
                theme: model.settings.theme,
                style: model.settings.boardStyle,
                cap: model.settings.bridgeCap,
                guideDots: true,
                highlightsLastMove: !session.state.isOver
            )
            .overlay {
                if session.state.winner != nil {
                    WinningPathCelebration(state: session.state, style: model.settings.boardStyle, cap: model.settings.bridgeCap)
                        .id(session.state.moveCount)
                }
            }
            .contentShape(.rect)
            .gesture(
                SpatialTapGesture().onEnded { value in
                    let move = geometry.nearestCell(to: value.location) { session.state.isLegal($0) }
                    if let move { session.play(move) }
                }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.smooth(duration: 0.18), value: session.state.moveCount)
    }

    @ViewBuilder
    private func controls(_ session: PuzzleSession) -> some View {
        HStack(spacing: 0) {
            switch session.status {
            case .solved, .showingSolution:
                barButton("Next Puzzle", "arrow.right", prominent: true) { Task { await session.next() } }
            case .missed:
                barButton("Try Again", "arrow.counterclockwise", prominent: true) { session.restart() }
                Divider().frame(height: 22)
                barButton("Show Solution", "lightbulb") { Task { await session.showSolution() } }
            default:
                barButton("Start Over", "arrow.counterclockwise") { session.restart() }
                    .disabled(session.status != .yourMove || session.state == session.puzzle?.state)
                Divider().frame(height: 22)
                barButton("Show Solution", "lightbulb") { Task { await session.showSolution() } }
                    .disabled(session.status != .yourMove)
                Divider().frame(height: 22)
                barButton("Skip", "forward") { Task { await session.next() } }
            }
        }
        .padding(4)
        .puzzleGlass()
        .fixedSize()
    }

    private func barButton(_ title: String, _ symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(prominent ? .semibold : .medium))
                .foregroundStyle(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    @ViewBuilder
    func puzzleGlass() -> some View {
        #if os(visionOS)
        glassBackgroundEffect(in: .capsule)
        #else
        glassEffect(.regular.interactive(), in: .capsule)
        #endif
    }
}
