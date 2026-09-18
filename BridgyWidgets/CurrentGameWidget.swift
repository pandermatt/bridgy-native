import BridgyLive
import SwiftUI
import WidgetKit

struct CurrentGameEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let board: UIImage?
}

struct CurrentGameProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrentGameEntry {
        CurrentGameEntry(
            date: .now,
            snapshot: WidgetSnapshot(title: "Your move", detail: "You vs Medium · 6×6", moves: 12, isYourTurn: true, isOver: false),
            board: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentGameEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrentGameEntry>) -> Void) {
        // Only the app changes the game, and it asks for a reload when it does.
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> CurrentGameEntry {
        let board = WidgetSnapshot.boardURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap(UIImage.init(data:))
        return CurrentGameEntry(date: .now, snapshot: WidgetSnapshot.load(), board: board)
    }
}

/// The game in progress on the home screen: the board as it stands, whose
/// move it is, and a tap straight back in. With no game, a way to start one
/// or to try a puzzle.
struct CurrentGameWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrentGame", provider: CurrentGameProvider()) { entry in
            CurrentGameView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Current Game")
        .description("Your game in progress, one tap from your next move.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

private struct CurrentGameView: View {
    let entry: CurrentGameEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryRectangular: rectangular(snapshot)
            case .systemMedium: medium(snapshot)
            default: small(snapshot)
            }
        } else {
            empty
        }
    }

    private func board(_ size: CGFloat) -> some View {
        Group {
            if let image = entry.board {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "square.grid.3x3").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private func small(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            board(90).frame(maxWidth: .infinity)
            Text(snapshot.title).font(.headline).lineLimit(1)
            Text("\(snapshot.moves) moves").font(.caption2).foregroundStyle(.secondary)
        }
        .widgetURL(WidgetSnapshot.continueURL)
    }

    private func medium(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 14) {
            board(130)
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.title).font(.title3.weight(.semibold))
                Text(snapshot.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text("\(snapshot.moves) moves").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if snapshot.isOver {
                    Link(destination: WidgetSnapshot.newGameURL) {
                        Label("New Game", systemImage: "arrow.clockwise").font(.caption.weight(.semibold))
                    }
                } else {
                    Text(snapshot.isYourTurn ? "Tap to play" : "Tap to watch")
                        .font(.caption.weight(.semibold)).foregroundStyle(.tint)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(WidgetSnapshot.continueURL)
    }

    private func rectangular(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Bridgy", systemImage: "square.grid.3x3").font(.caption2)
            Text(snapshot.title).font(.headline)
            Text(snapshot.detail).font(.caption2).lineLimit(1)
        }
        .widgetURL(WidgetSnapshot.continueURL)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Bridgy", systemImage: "square.grid.3x3").font(.headline)
            if family == .accessoryRectangular {
                Text("No game in progress").font(.caption)
            } else {
                Link(destination: WidgetSnapshot.newGameURL) {
                    Label("New Game", systemImage: "play.fill")
                }
                Link(destination: WidgetSnapshot.puzzleURL) {
                    Label("Random Puzzle", systemImage: "puzzlepiece.extension")
                }
            }
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetSnapshot.newGameURL)
    }
}
