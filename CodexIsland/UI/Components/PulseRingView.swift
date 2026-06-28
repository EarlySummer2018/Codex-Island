import SwiftUI

struct PulseRingView: View {
    var size: CGFloat = 16

    @State private var isAnimating = false

    var body: some View {
        Circle()
            .stroke(Color(red: 0.94, green: 0.27, blue: 0.27), lineWidth: max(size / 10, 1))
            .frame(width: size, height: size)
            .scaleEffect(isAnimating ? 1.9 : 0.75)
            .opacity(isAnimating ? 0 : 0.85)
            .onAppear {
                isAnimating = false
                withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
            .accessibilityHidden(true)
    }
}
