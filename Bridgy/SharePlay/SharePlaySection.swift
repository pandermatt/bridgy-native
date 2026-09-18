import GroupActivities
import SwiftUI

/// Play against someone on your FaceTime call, each on your own device.
///
/// During a call it's one button. Outside one, the share sheet's SharePlay
/// option starts a call with the game already attached.
struct SharePlaySection: View {
    let size: Int
    @Environment(AppModel.self) private var model
    @StateObject private var call = GroupStateObserver()

    var body: some View {
        Section {
            if call.isEligibleForGroupSession {
                Button {
                    Task { await model.sharePlay.start(size: size) }
                } label: {
                    row("Play with Your Call", "You play Down, they play Across, on a \(size)×\(size) board.")
                }
            } else {
                ShareLink(item: BridgyActivity(size: size), preview: SharePreview("Play Bridgy", image: Image("ShareIcon"))) {
                    row("Play with a Friend", "Over SharePlay, each on your own device.")
                }
            }
        }
    }

    private func row(_ title: String, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                // Plain colours, as the Puzzle row below has: a link's tint
                // would otherwise wash the caption out to pale blue.
                Text(title).foregroundStyle(Color.primary)
                Text(detail).font(.caption).foregroundStyle(Color.secondary)
            }
        } icon: {
            Image(systemName: "shareplay").foregroundStyle(Color.accentColor)
        }
    }
}

/// "Anna left the game", along the top for a few seconds.
struct SharePlayNotice: View {
    @Bindable var sharePlay: SharePlayGame

    var body: some View {
        if let notice = sharePlay.notice {
            Label(notice, systemImage: "shareplay")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .noticeGlass()
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { sharePlay.notice = nil }
                }
        }
    }
}

private extension View {
    @ViewBuilder
    func noticeGlass() -> some View {
        #if os(visionOS)
        glassBackgroundEffect(in: .capsule)
        #else
        glassEffect(.regular, in: .capsule)
        #endif
    }
}
