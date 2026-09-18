@preconcurrency import AVFoundation
import Foundation
import MusicKit
import Observation
import os

private let musicLog = Logger(subsystem: "ch.pandermatt.bridgy", category: "VictorySong")

/// Why a song could not be offered.
enum SongPreviewError: LocalizedError, Equatable {
    case notAuthorized
    case notFound
    case noPreview

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "Bridgy needs access to Apple Music to suggest a song."
        case .notFound: "That song isn't in the Apple Music catalogue here."
        case .noPreview: "Apple Music has no preview of this song in your region."
        }
    }
}

/// Fetches a catalogue song with MusicKit and plays a short stretch of its
/// official 30-second preview — which needs no subscription.
///
/// One engine for the whole app, so two cards can never play over each other.
/// It never owns the audio session outright: Bridgy's own tones already hold
/// it as `.ambient`, mixing with whatever the player is listening to and
/// honouring the silent switch, and a preview joins them on those terms.
@MainActor
@Observable
final class AudioEngine {

    enum Phase: Equatable {
        case idle
        case loading
        case ready(Song)
        case failed(SongPreviewError)
    }

    /// How much of the preview a tap plays. Playback stops early; the preview
    /// itself is never altered.
    static let snippet: Duration = .seconds(10)
    private static let fade: Duration = .milliseconds(600)

    private(set) var phase: Phase = .idle
    private(set) var isPlaying = false
    /// 0...1 through the current play.
    private(set) var progress: Double = 0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var loadedID: MusicItemID?
    /// How long this play should last: the snippet, or the whole preview.
    @ObservationIgnored private var limit: Duration = snippet

    var song: Song? {
        if case .ready(let song) = phase { return song }
        return nil
    }

    // MARK: - Loading

    /// Loads the song once; later calls for the same id are free.
    func load(id: MusicItemID) async {
        if loadedID == id, case .ready = phase { return }
        stop()
        phase = .loading
        do {
            let song = try await Self.fetch(id: id)
            loadedID = id
            phase = .ready(song)
        } catch let error as SongPreviewError {
            musicLog.notice("No victory song: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error)
        } catch {
            musicLog.error("Catalogue request failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(.notFound)
        }
    }

    private static func fetch(id: MusicItemID) async throws -> Song {
        switch MusicAuthorization.currentStatus {
        case .authorized: break
        case .notDetermined:
            guard await MusicAuthorization.request() == .authorized else { throw SongPreviewError.notAuthorized }
        default:
            throw SongPreviewError.notAuthorized
        }
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: id)
        guard let song = try await request.response().items.first else { throw SongPreviewError.notFound }
        guard song.previewAssets?.first?.url != nil else { throw SongPreviewError.noPreview }
        return song
    }

    // MARK: - Playback

    /// Plays from the start of the preview: the snippet, or all of it.
    func play(fullPreview: Bool = false) {
        guard let url = song?.previewAssets?.first?.url else { return }
        stop()
        #if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        limit = fullPreview ? .seconds(30) : Self.snippet
        let seconds = Double(limit.components.seconds)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.progress = min(1, time.seconds / seconds)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }

        player.play()
        isPlaying = true
        progress = 0

        let limit = limit
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: limit - Self.fade)
            guard !Task.isCancelled else { return }
            await self?.fadeOutAndStop()
        }
    }

    /// A short fade inside the limit, so the cut doesn't click.
    private func fadeOutAndStop() async {
        guard let player else { return }
        let steps = 12
        for step in 1...steps {
            if Task.isCancelled { return }
            player.volume = Float(1 - Double(step) / Double(steps))
            try? await Task.sleep(for: Self.fade / steps)
        }
        stop()
    }

    /// Stops and lets go of everything: timer, observers, player. Safe to call
    /// any number of times; called on dismissal and when the app backgrounds.
    func stop() {
        stopTask?.cancel()
        stopTask = nil
        if let player, let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isPlaying = false
        progress = 0
    }
}
