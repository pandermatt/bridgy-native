import AVFoundation
import Foundation

/// Synthesises the game's sounds rather than shipping audio files.
///
/// Two cues: a soft plucked tone when a piece lands, rising in pitch as a chain
/// grows so a run of moves reads as a phrase, and a short major arpeggio on a
/// win. Everything is generated into PCM buffers at launch.
///
/// The important detail is that `scheduleBuffer` **appends to a playback queue**.
/// Each tone is 0.16 s, so at fifteen moves a second every move queued more audio
/// than there was time to play it, and a long game banked minutes of sound that
/// kept going after the board was finished. Tones now interrupt rather than
/// queue, they are rate-limited, and `stopAll()` exists for the moment the game
/// ends.
@MainActor
final class SoundGenerator {

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var tones: [Int: AVAudioPCMBuffer] = [:]
    private var started = false
    private var lastTone: ContinuousClock.Instant?
    private var winTasks: [Task<Void, Never>] = []

    /// Semitones above A3 for the move sound, cycling so it never climbs away.
    private static let moveLadder = [0, 2, 4, 7, 9, 12, 9, 7, 4, 2]
    private static let winArpeggio = [12, 16, 19, 24]

    /// Closer together than this and it is a buzz, not feedback.
    private static let minimumGap = Duration.milliseconds(120)
    /// Above this pace, move tones are dropped entirely.
    private static let maximumPace = 8.0

    func prepare() {
        guard !started else { return }
        started = true
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        for semitone in Set(Self.moveLadder + Self.winArpeggio) {
            tones[semitone] = makeTone(semitone: semitone, duration: 0.16, format: format)
        }
        try? engine.start()
        player.play()
    }

    /// `pace` is non-nil only while two computers are playing.
    func playMove(index: Int, pace: WatchPace?) {
        guard started else { return }
        if let pace, pace.movesPerSecond > Self.maximumPace { return }

        let now = ContinuousClock().now
        if let lastTone, now - lastTone < Self.minimumGap { return }
        lastTone = now

        let semitone = Self.moveLadder[abs(index) % Self.moveLadder.count]
        schedule(semitone, interrupting: true)
    }

    func playWin() {
        guard started else { return }
        stopAll()
        for (step, semitone) in Self.winArpeggio.enumerated() {
            guard step > 0 else {
                schedule(semitone, interrupting: true)
                continue
            }
            let task = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Double(step) * 0.11))
                guard !Task.isCancelled else { return }
                self?.schedule(semitone, interrupting: false)
            }
            winTasks.append(task)
        }
    }

    /// Silences everything pending. Without this the queue outlives the game.
    func stopAll() {
        for task in winTasks { task.cancel() }
        winTasks.removeAll()
        guard started else { return }
        player.stop()
        player.play()
        lastTone = nil
    }

    private func schedule(_ semitone: Int, interrupting: Bool) {
        guard let buffer = tones[semitone] else { return }
        player.scheduleBuffer(
            buffer,
            at: nil,
            options: interrupting ? [.interrupts] : [],
            completionHandler: nil
        )
    }

    /// A plucked tone: fundamental plus a quieter octave, under a fast attack
    /// and an exponential decay, so it reads as a tap rather than a beep.
    private func makeTone(semitone: Int, duration: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames

        let frequency = 220.0 * pow(2.0, Double(semitone) / 12.0)
        let attackFrames = sampleRate * 0.004
        for frame in 0..<Int(frames) {
            let time = Double(frame) / sampleRate
            let phase = 2 * Double.pi * frequency * time
            let tone = sin(phase) + 0.28 * sin(2 * phase)
            let attack = min(1.0, Double(frame) / attackFrames)
            let decay = exp(-5.5 * time / duration)
            samples[frame] = Float(tone * attack * decay * 0.18)
        }
        return buffer
    }
}
