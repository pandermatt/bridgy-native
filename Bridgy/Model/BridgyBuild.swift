import Foundation

/// Facts about how this copy of the app was built.
enum BridgyBuild {
    /// Signed with iCloud and SharePlay (Group Activities). A free Personal
    /// Team can't provision either, so those builds leave both features out
    /// rather than crash on them. Set by `BRIDGY_ENTITLEMENTS` in project.yml.
    static let hasPaidEntitlements =
        Bundle.main.object(forInfoDictionaryKey: "BridgyEntitlements") as? String == "Paid"
}
