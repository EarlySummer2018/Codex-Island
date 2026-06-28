import SwiftUI

struct TokenPill: View {
    let label: String
    let value: Int
    let color: Color
    var suffix: String?
    var width: CGFloat = 48
    var alignment: TokenPillAlignment = .leading

    var body: some View {
        VStack(alignment: alignment.horizontal, spacing: 1) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(color.opacity(0.74))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let suffix {
                    Text(suffix)
                        .font(.system(size: 7, weight: .regular, design: .monospaced))
                        .foregroundStyle(color.opacity(0.64))
                        .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment.frame)

            AnimatedTokenCounter(
                value: value,
                font: .system(size: 12, weight: .bold, design: .monospaced),
                color: color,
                alignment: alignment.frame
            )
        }
        .frame(width: width, height: 24, alignment: alignment.frame)
    }
}

enum TokenPillAlignment {
    case leading
    case trailing

    var horizontal: HorizontalAlignment {
        switch self {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        }
    }

    var frame: Alignment {
        switch self {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        }
    }
}
