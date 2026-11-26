import SwiftUI

// Controls shared by the notch card and the fullscreen stage.

/// White dot with an expanding halo; static under Reduce Motion.
struct WaitingPulse: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(.white.opacity(pulsing ? 0 : 0.6))
                    .scaleEffect(pulsing ? 2.8 : 1)
            )
            .shadow(color: .white.opacity(0.8), radius: 3)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulsing = true }
            }
    }
}

/// Capsule button: white "prominent" (Done) or translucent (Skip). `height` scales the type with it.
struct PillButtonStyle: ButtonStyle {
    let prominent: Bool
    var height: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height * 0.48, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .padding(.horizontal, height * 0.54)
            .frame(height: height)
            .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.16)))
            .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0 : 0.18), lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Round "⋯" button that opens the sequence menu.
struct MoreButton: View {
    var diameter: CGFloat = 26
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.system(size: diameter * 0.46, weight: .bold))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}
