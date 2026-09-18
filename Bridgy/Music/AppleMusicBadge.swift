import SwiftUI

/// "Listen on Apple Music", linking to the song.
///
/// TODO(badge): this is a stand-in. App Review requires Apple's official
/// badge artwork, unmodified — download it from Apple Music Marketing Tools
/// (https://tools.applemusic.com), add it to the asset catalogue as
/// "ListenOnAppleMusic", and replace the label below with
/// `Image("ListenOnAppleMusic")`. Keep the link.
struct AppleMusicBadge: View {
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.caption.weight(.bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Listen on").font(.system(size: 8, weight: .medium))
                    Text("Apple Music").font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black, in: .rect(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
        }
        .accessibilityLabel("Listen on Apple Music")
    }
}
