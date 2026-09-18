#if os(iOS)
import ActivityKit
import AppIntents
import Foundation
import os

let runActivityLog = Logger(subsystem: "ch.pandermatt.bridgy", category: "LiveActivity")

/// A long run — training an agent or an experiment — shown as a Live Activity.
///
/// Shared between the app, which starts and updates it, and the widget
/// extension, which draws it on the Lock Screen and in the Dynamic Island.
public struct RunActivityAttributes: ActivityAttributes {
    public enum Kind: String, Codable, Hashable, Sendable {
        case training, experiment

        public var symbol: String { self == .training ? "brain.head.profile" : "flask" }
    }

    public struct ContentState: Codable, Hashable, Sendable {
        /// 0...1, or nil when the length is unknown (a hypothesis test).
        public var progress: Double?
        public var headline: String
        public var detail: String
        public var finished = false

        public init(progress: Double?, headline: String, detail: String, finished: Bool = false) {
            self.progress = progress
            self.headline = headline
            self.detail = detail
            self.finished = finished
        }
    }

    public var kind: Kind
    public var title: String

    public init(kind: Kind, title: String) {
        self.kind = kind
        self.title = title
    }
}

/// The Stop button on the Live Activity.
///
/// Defined once, here, for both the app and the widget extension: the system
/// names the intent by its Swift type, and a copy compiled into each target
/// would be two different types — the app never matched the extension's, and
/// the button silently did nothing. As a LiveActivityIntent it runs in the
/// app, where `RunStopper` has the handlers.
public struct StopRunIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Stop"
    public static let isDiscoverable = false

    @Parameter(title: "Kind") public var kind: String

    public init() {}
    public init(kind: RunActivityAttributes.Kind) { self.kind = kind.rawValue }

    public func perform() async throws -> some IntentResult {
        runActivityLog.notice("StopRunIntent.perform kind=\(kind, privacy: .public)")
        if let kind = RunActivityAttributes.Kind(rawValue: kind) {
            await MainActor.run { RunStopper.stop(kind) }
        }
        return .result()
    }
}

/// Where the Stop button and a dismissed activity reach the running work.
/// Empty in the widget extension, where nothing runs.
@MainActor
public enum RunStopper {
    public static var handlers: [RunActivityAttributes.Kind: () -> Void] = [:]

    public static func stop(_ kind: RunActivityAttributes.Kind) {
        runActivityLog.notice("RunStopper.stop \(kind.rawValue, privacy: .public) handler=\(handlers[kind] != nil)")
        handlers[kind]?()
    }
}

/// Lets the app and the extension include this module's intents.
public struct BridgyLiveIntents: AppIntentsPackage {}
#endif
