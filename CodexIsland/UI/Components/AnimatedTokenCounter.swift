import SwiftUI

struct AnimatedTokenCounter: View {
    let value: Int
    let font: Font
    let color: Color
    var alignment: Alignment = .leading

    @State private var displayValue = 0
    @State private var isFlashing = false
    @State private var flashTask: DispatchWorkItem?

    private var formattedValue: String {
        TokenFormatter.format(displayValue)
    }

    var body: some View {
        counterText
            .frame(maxWidth: .infinity, alignment: alignment)
            .onAppear {
                displayValue = value
            }
            .onChange(of: value) { newValue in
                guard newValue != displayValue else {
                    return
                }

                flash()

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    displayValue = newValue
                }
            }
            .onDisappear {
                flashTask?.cancel()
                flashTask = nil
            }
    }

    @ViewBuilder
    private var counterText: some View {
        let text = Text(formattedValue)
            .font(font)
            .foregroundStyle(isFlashing ? Color.white : color)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.78)

        if #available(macOS 14.0, *) {
            text.contentTransition(.numericText(countsDown: false))
        } else {
            text
                .id(formattedValue)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
        }
    }

    private func flash() {
        flashTask?.cancel()

        withAnimation(.easeOut(duration: 0.1)) {
            isFlashing = true
        }

        let task = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.2)) {
                isFlashing = false
            }
        }

        flashTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }
}
