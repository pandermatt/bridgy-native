import Foundation

/// Mirrors a long run in a Live Activity, and stops the run if the activity is
/// dismissed or its Stop button is pressed.
///
/// A no-op everywhere but iPhone and iPad, so callers need no conditions.
@MainActor
final class RunActivityController {
    #if os(iOS)
    private let kind: RunActivityAttributes.Kind
    private var activity: Activity<RunActivityAttributes>?
    private var watcher: Task<Void, Never>?
    /// Set when the app ends the activity itself, so that ending is not taken
    /// for the person dismissing it.
    private var endingOurselves = false
    private var lastUpdate = ContinuousClock.now
    private var pending: RunActivityAttributes.ContentState?
    #endif

    enum Kind { case training, experiment }

    init(kind: Kind, onStop: @escaping @MainActor () -> Void) {
        #if os(iOS)
        let k: RunActivityAttributes.Kind = kind == .training ? .training : .experiment
        self.kind = k
        RunStopper.handlers[k] = onStop
        self.onStop = onStop
        #endif
    }

    #if os(iOS)
    private let onStop: @MainActor () -> Void
    #endif

    func start(title: String, headline: String) {
        #if os(iOS)
        end(finalHeadline: nil)
        // A finished run's card lingers on the Lock Screen; a new run of the
        // same kind replaces it rather than stacking behind it.
        let stale = Activity<RunActivityAttributes>.activities
            .filter { $0.attributes.kind == kind }
            .map(\.id)
        Task {
            for id in stale { await Self.find(id)?.end(nil, dismissalPolicy: .immediate) }
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endingOurselves = false
        let state = RunActivityAttributes.ContentState(progress: 0, headline: headline, detail: "")
        do {
            let activity = try Activity.request(
                attributes: RunActivityAttributes(kind: kind, title: title),
                content: .init(state: state, staleDate: nil)
            )
            self.activity = activity
            let id = activity.id
            watcher = Task { [weak self] in
                guard let updates = Self.find(id)?.activityStateUpdates else { return }
                for await state in updates {
                    guard let self else { return }
                    // Swiped away while still running: the person wants it gone,
                    // and the run with it.
                    if state == .dismissed, !self.endingOurselves {
                        self.activity = nil
                        self.onStop()
                        return
                    }
                    if state == .ended || state == .dismissed { return }
                }
            }
        } catch {
            activity = nil
        }
        #endif
    }

    /// Updates at most every couple of seconds; the system budgets updates.
    func update(progress: Double?, headline: String, detail: String) {
        #if os(iOS)
        guard let activity else { return }
        let state = RunActivityAttributes.ContentState(progress: progress, headline: headline, detail: detail)
        pending = state
        let now = ContinuousClock.now
        guard now - lastUpdate > .seconds(2) else { return }
        lastUpdate = now
        pending = nil
        let id = activity.id
        Task { await Self.find(id)?.update(.init(state: state, staleDate: nil)) }
        #endif
    }

    /// Ends the activity, leaving a final line on the Lock Screen briefly.
    func end(finalHeadline: String?, detail: String = "") {
        #if os(iOS)
        watcher?.cancel()
        watcher = nil
        guard let activity else { return }
        endingOurselves = true
        self.activity = nil
        let final = RunActivityAttributes.ContentState(
            progress: pending?.progress ?? 1, headline: finalHeadline ?? "Stopped", detail: detail, finished: true
        )
        let id = activity.id
        let policy: ActivityUIDismissalPolicy = finalHeadline == nil ? .immediate : .after(.now + 60 * 15)
        Task { await Self.find(id)?.end(.init(state: final, staleDate: nil), dismissalPolicy: policy) }
        #endif
    }

    #if os(iOS)
    /// Activities are looked up by id inside tasks: the handle itself is not
    /// Sendable and cannot be carried across.
    private nonisolated static func find(_ id: String) -> Activity<RunActivityAttributes>? {
        Activity<RunActivityAttributes>.activities.first { $0.id == id }
    }
    #endif
}

#if os(iOS)
import ActivityKit
import AppIntents
import BridgyLive

/// Includes the shared module's intents, so the Live Activity's Stop resolves.
struct BridgyAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [BridgyLiveIntents.self] }
}
#endif
