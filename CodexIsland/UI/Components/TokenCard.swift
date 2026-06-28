import SwiftUI

struct TokenCard: View {
    let title: String
    let value: Int
    let color: Color
    var note: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)

            AnimatedTokenCounter(
                value: value,
                font: .system(size: 16, weight: .bold, design: .monospaced),
                color: color,
                alignment: .center
            )
            .frame(height: 19)

            Text(note ?? " ")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundStyle(color.opacity(note == nil ? 0 : 0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .padding(.vertical, 7)
        .padding(.horizontal, 5)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
