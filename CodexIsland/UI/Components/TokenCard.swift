import SwiftUI

struct TokenCard: View {
    let title: String
    private let value: Int?
    private let textValue: String?
    let color: Color
    var note: String?

    init(title: String, value: Int, color: Color, note: String? = nil) {
        self.title = title
        self.value = value
        self.textValue = nil
        self.color = color
        self.note = note
    }

    init(title: String, text: String, color: Color, note: String? = nil) {
        self.title = title
        self.value = nil
        self.textValue = text
        self.color = color
        self.note = note
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)

            Group {
                if let value {
                    AnimatedTokenCounter(
                        value: value,
                        font: .system(size: 14, weight: .bold, design: .monospaced),
                        color: color,
                        alignment: .center
                    )
                } else {
                    Text(textValue ?? "0.0%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(height: 16)

            Text(note ?? " ")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(color.opacity(note == nil ? 0 : 0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.035, green: 0.035, blue: 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }
}
