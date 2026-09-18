import ActivityKit
import BridgyLive
import AppIntents
import SwiftUI
import WidgetKit

@main
struct BridgyWidgets: WidgetBundle {
    var body: some Widget {
        RunLiveActivity()
        CurrentGameWidget()
    }
}

/// Training and experiments on the Lock Screen and in the Dynamic Island.
struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenView(context: context)
                .padding()
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: context.attributes.kind.symbol)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let progress = context.state.progress {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .font(.headline.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.headline).font(.subheadline)
                        if let progress = context.state.progress {
                            ProgressView(value: progress)
                        }
                        HStack {
                            Text(context.state.detail).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if !context.state.finished {
                                StopButton(kind: context.attributes.kind)
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.kind.symbol)
            } compactTrailing: {
                if let progress = context.state.progress {
                    Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                } else {
                    Image(systemName: "hourglass")
                }
            } minimal: {
                Image(systemName: context.attributes.kind.symbol)
            }
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<RunActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(context.attributes.title, systemImage: context.attributes.kind.symbol)
                    .font(.headline)
                Spacer()
                if let progress = context.state.progress {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .font(.headline.monospacedDigit())
                }
            }
            Text(context.state.headline).font(.subheadline)
            if let progress = context.state.progress {
                ProgressView(value: progress)
            }
            HStack {
                Text(context.state.detail).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !context.state.finished {
                    StopButton(kind: context.attributes.kind)
                }
            }
        }
    }
}

private struct StopButton: View {
    let kind: RunActivityAttributes.Kind

    var body: some View {
        Button(intent: StopRunIntent(kind: kind)) {
            Label("Stop", systemImage: "stop.fill").font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }
}

/// Includes the shared module's intents, so the Stop button resolves.
struct BridgyWidgetIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [BridgyLiveIntents.self] }
}
