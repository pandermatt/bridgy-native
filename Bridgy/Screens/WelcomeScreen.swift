import SwiftUI

/// Shown once on first launch, and again from Rules on request.
///
/// Bridg-It is obscure enough that landing straight on a lattice of coloured
/// dots is bewildering. This is the Apple pattern for saying what an app is:
/// a mark, a name, a handful of rows, one button.
struct WelcomeScreen: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    header
                    VStack(alignment: .leading, spacing: 26) {
                        row(
                            "Two grids, interleaved",
                            "square.grid.3x3",
                            """
                            You own one grid of dots, your opponent the other. They overlap so \
                            every bridge you could build crosses exactly one of theirs.
                            """
                        )
                        row(
                            "Build and block at once",
                            "hand.tap",
                            """
                            Tap the gap between two of your dots to bridge them. Taking that gap \
                            also denies it to your opponent — there is no purely defensive move.
                            """
                        )
                        row(
                            "Cross the board",
                            "arrow.up.and.down",
                            """
                            Down moves first and needs a chain from top to bottom. Across needs \
                            one from left to right.
                            """
                        )
                        row(
                            "Somebody always wins",
                            "checkmark",
                            """
                            There are no draws. When the board fills, exactly one player has \
                            crossed it — never both, because their bridges would have to cross.
                            """
                        )
                    }
                }
                .padding(28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }

            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .prominentAction()
            .controlSize(.large)
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            mark
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text("Bridgy")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("A connection game by David Gale")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
    }

    /// The app's motif: blue has crossed, and in doing so has cut red in half.
    private var mark: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let thickness = side * 0.13
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                    .fill(Color(hex: "132B49"))
                HStack(spacing: thickness * 1.5) {
                    Capsule().fill(Color(hex: "FF2539")).frame(width: side * 0.22, height: thickness)
                    Capsule().fill(Color(hex: "FF2539")).frame(width: side * 0.22, height: thickness)
                }
                Capsule()
                    .fill(Color(hex: "6DAEEB"))
                    .frame(width: thickness, height: side * 0.62)
            }
        }
        .accessibilityHidden(true)
    }

    private func row(_ title: String, _ symbol: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
