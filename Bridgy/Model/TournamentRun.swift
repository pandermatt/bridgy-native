import BridgyEngine
import Foundation
import Observation

/// Runs a tournament and publishes the analysis as it fills in.
///
/// Every outcome is folded into a private working copy; the published one is
/// replaced on a throttle, so a run of thousands of games redraws the charts a
/// few times a second rather than thousands of times.
@MainActor
@Observable
final class TournamentRun {

    private(set) var analysis: TournamentAnalysis?
    private(set) var isRunning = false
    var configuration = TournamentConfiguration(minimumSize: 4, maximumSize: 6, gamesPerColour: 3)

    private var task: Task<Void, Never>?
    private static let publishInterval = Duration.milliseconds(120)

    var totalGames: Int {
        configuration.totalGames(participants: Difficulty.allCases.count)
    }

    var progress: Double {
        guard let analysis, totalGames > 0 else { return 0 }
        return min(1, Double(analysis.gamesPlayed) / Double(totalGames))
    }

    func start() {
        stop()
        let settings = configuration
        let participants = Tournament.defaultParticipants(forSize: settings.maximumSize)
        var working = TournamentAnalysis(
            participants: participants.map(\.name),
            configuration: settings
        )
        analysis = working
        isRunning = true

        task = Task { [weak self] in
            let clock = ContinuousClock()
            var lastPublish = clock.now
            for await outcome in Tournament.stream(configuration: settings, participants: participants) {
                working.record(outcome)
                if clock.now - lastPublish >= Self.publishInterval {
                    lastPublish = clock.now
                    self?.analysis = working
                }
            }
            working.finish()
            guard let self, !Task.isCancelled else { return }
            self.analysis = working
            self.isRunning = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Writes the report somewhere `ShareLink` can pick it up.
    func exportURL() -> URL? {
        guard let analysis else { return nil }
        let url = URL.temporaryDirectory.appendingPathComponent("bridgy-tournament.csv")
        guard let data = analysis.csv().data(using: .utf8) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }
}
