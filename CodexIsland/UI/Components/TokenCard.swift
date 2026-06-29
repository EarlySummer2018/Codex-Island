import SwiftUI

struct TokenCard: View {
    let title: String
    let value: Int
    let color: Color
    var note: String?

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)

            AnimatedTokenCounter(
                value: value,
                font: .system(size: 13, weight: .bold, design: .monospaced),
                color: color,
                alignment: .center
            )
            .frame(height: 15)

            Text(note ?? " ")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(color.opacity(note == nil ? 0 : 0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.035, green: 0.035, blue: 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(color.opacity(0.42))
                .frame(height: 1)
                .padding(.horizontal, 8)
        }
    }
}
