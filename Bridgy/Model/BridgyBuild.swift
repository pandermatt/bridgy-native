import Foundation

/// Facts about how this copy of the app was built.
enum BridgyBuild {
    /// Signed with iCloud and SharePlay (Group Activities). A free Personal
    /// Team can't provision either, so those builds leave both features out
    /// rather than crash on them. Set by `BRIDGY_ENTITLEMENTS` in project.yml.
    static let hasPaidEntitlements =
        Bundle.main.object(forInfoDictionaryKey: "BridgyEntitlements") as? String == "Paid"

    /// The victory song, offered once Apple Music is set up for the app: the
    /// MusicKit service enabled on the App ID (a paid membership) and the
    /// official "Listen on Apple Music" badge in place of the placeholder.
    /// Until then the setting and the song are hidden.
    static let musicKitReady = false
}
