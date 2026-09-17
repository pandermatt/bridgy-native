import SwiftUI

/// The first thing you see: a title over the backdrop and a stack of glass tiles.
struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    var onSelect: (Destination) -> Void
    var onResume: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        if model.canResume {
                            GlassTile(
                                title: "Resume",
                                subtitle: model.configuration.summary,
                                symbolName: "play.circle",
                                isProminent: true,
                                action: onResume
                            )
                        }
                        ForEach(Destination.allCases) { destination in
                            GlassTile(
                                title: destination == .play && !model.canResume ? "New Game" : destination.title,
                                subtitle: destination.subtitle,
                                symbolName: destination.symbolName,
                                isProminent: destination == .play && !model.canResume
                            ) {
                                onSelect(destination)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background { BackdropView(backdrop: model.settings.backdrop) }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Bridgy")
                .font(.system(size: 52, weight: .bold, design: .rounded))
            Text("A connection game by David Gale")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }
}
