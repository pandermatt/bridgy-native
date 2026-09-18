import BridgyEngine
import CoreTransferable
import Foundation
import Observation
import UniformTypeIdentifiers

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

    /// The field. Each engine is rebuilt for every board size it plays.
    var participants: [Participant] { Tournament.defaultParticipants() }

    var totalGames: Int {
        configuration.totalGames(participants: participants.count)
    }

    var progress: Double {
        guard let analysis, totalGames > 0 else { return 0 }
        return min(1, Double(analysis.gamesPlayed) / Double(totalGames))
    }

    func start() {
        stop()
        let settings = configuration
        let participants = participants
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

    /// The current results, ready to share. Nothing is built or written until
    /// someone actually shares it.
    var report: TournamentReport? { analysis.map(TournamentReport.init) }
}

/// The results as a CSV file, produced only at the moment of sharing.
///
/// This replaced a function called from the view body that built the whole
/// CSV and wrote it to disk on the main thread every time the screen refreshed
/// — about eight times a second while a tournament ran.
struct TournamentReport: Transferable {
    let analysis: TournamentAnalysis

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { report in
            Data(report.analysis.csv().utf8)
        }
        .suggestedFileName("bridgy-tournament.csv")
    }
}
