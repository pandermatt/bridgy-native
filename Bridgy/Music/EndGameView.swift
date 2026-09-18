import MusicKit
import SwiftUI

/// A song to celebrate a win: artwork, title, artist, a tap to hear ten
/// seconds of the Apple Music preview, and a way to the full song.
///
/// Nothing plays until the player taps. If the song can't be offered — no
/// permission, not in this region's catalogue, no preview — the card simply
/// isn't there.
struct EndGameView: View {
    let songID: MusicItemID
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    private var engine: AudioEngine { model.audio }

    var body: some View {
        Group {
            switch engine.phase {
            case .idle, .loading:
                card(title: "Victory song", artist: "Finding a track…", artwork: nil, url: nil)
                    .redacted(reason: .placeholder)
            case .ready(let song):
                card(title: song.title, artist: song.artistName, artwork: song.artwork, url: song.url)
            case .failed:
                EmptyView()
            }
        }
        .task(id: songID) { await engine.load(id: songID) }
        .onDisappear { engine.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { engine.stop() }
        }
    }

    private func card(title: String, artist: String, artwork: Artwork?, url: URL?) -> some View {
        HStack(spacing: 12) {
            Group {
                if let artwork {
                    ArtworkImage(artwork, width: 56, height: 56)
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("Victory song").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(title).font(.headline).lineLimit(1)
                Text(artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if let url {
                    AppleMusicBadge(url: url).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            playButton
        }
        .padding(10)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
        .contextMenu {
            if engine.song != nil {
                Button { engine.play(fullPreview: true) } label: {
                    Label("Play Full Preview", systemImage: "play.circle")
                }
            }
        }
        .frame(maxWidth: 440)
    }

    private var playButton: some View {
        Button {
            engine.isPlaying ? engine.stop() : engine.play()
        } label: {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: engine.progress)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: engine.progress)
                Image(systemName: engine.isPlaying ? "stop.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(engine.song == nil)
        .accessibilityLabel(engine.isPlaying ? "Stop preview" : "Play a 10-second preview")
    }
}
