/// A deterministic `RandomNumberGenerator` (SplitMix64).
///
/// Every engine draws from an injected generator rather than the global one, so
/// a match can be replayed exactly — which is what makes the strength tests and
/// the tournament reproducible.
public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        // Guard against the all-zero state, which SplitMix64 handles fine but
        // which makes an accidental `seed: 0` look suspicious in logs.
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public init() {
        self.init(seed: UInt64.random(in: UInt64.min...UInt64.max))
    }

    /// Combines a base seed with an index into an independent seed, so games
    /// played in parallel each get their own stream without sharing one.
    public static func mix(_ seed: UInt64, _ index: UInt64) -> UInt64 {
        var z = seed &+ (index &+ 1) &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
