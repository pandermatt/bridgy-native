import SwiftUI

/// The handful of places where visionOS genuinely has no equivalent.
///
/// Liquid Glass is not one API across the family: `glassEffect`, `.glass` and
/// `.glassProminent` are all unavailable on visionOS, because a visionOS window
/// *is* already a glass material sitting in the room — there is nothing to layer
/// it on. `navigationSubtitle` has no slot there either. Keeping the branches
/// here rather than at each call site means a screen reads the same on every
/// platform, and there is one place to revisit if visionOS ever grows them.
extension View {

    /// A prominent, filled action: the share button, the welcome screen's
    /// continue.
    @ViewBuilder
    func prominentAction() -> some View {
        #if os(visionOS)
        buttonStyle(.borderedProminent)
        #else
        buttonStyle(.glassProminent)
        #endif
    }

    /// A secondary action sitting beside a prominent one.
    @ViewBuilder
    func secondaryAction() -> some View {
        #if os(visionOS)
        buttonStyle(.bordered)
        #else
        buttonStyle(.glass)
        #endif
    }

    /// Clear, interactive glass over an already-painted shape.
    ///
    /// On visionOS the shape is left as it is: the window is glass already, and
    /// the gradient underneath is the point.
    @ViewBuilder
    func interactiveGlass(in shape: some Shape) -> some View {
        #if os(visionOS)
        self
        #else
        glassEffect(.clear.interactive(), in: shape)
        #endif
    }

    /// The window subtitle, where the platform has one.
    @ViewBuilder
    func platformSubtitle(_ subtitle: String) -> some View {
        #if os(visionOS)
        self
        #else
        navigationSubtitle(subtitle)
        #endif
    }
}
