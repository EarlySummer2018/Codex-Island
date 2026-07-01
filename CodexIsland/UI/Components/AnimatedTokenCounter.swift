import SwiftUI

struct AnimatedTokenCounter: View {
    let value: Int
    let font: Font
    let color: Color
    var alignment: Alignment = .leading

    @State private var displayValue = 0

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

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    displayValue = newValue
                }
            }
    }

    @ViewBuilder
    private var counterText: some View {
        let text = Text(formattedValue)
            .font(font)
            .foregroundStyle(color)
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
}
