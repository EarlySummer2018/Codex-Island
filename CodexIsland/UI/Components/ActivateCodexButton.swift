import SwiftUI

struct ActivateCodexButton: View {
    enum Style {
        case compact
        case fullWidth
    }

    let title: String
    var style: Style = .compact

    @State private var isHovered = false

    var body: some View {
        Button(action: CodexActivation.activate) {
            Label(title, systemImage: "arrow.up.forward.app.fill")
                .labelStyle(.titleAndIcon)
                .font(font)
                .foregroundStyle(isHovered ? foregroundOnHover : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: style == .fullWidth ? .infinity : nil)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isHovered ? hoverBackground : normalBackground)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovered
            }
        }
    }

    private var font: Font {
        switch style {
        case .compact:
            return .system(size: 10, weight: .semibold, design: .rounded)
        case .fullWidth:
            return .system(size: 11, weight: .semibold, design: .rounded)
        }
    }

    private var horizontalPadding: CGFloat {
        style == .fullWidth ? 10 : 8
    }

    private var verticalPadding: CGFloat {
        style == .fullWidth ? 7 : 4
    }

    private var cornerRadius: CGFloat {
        style == .fullWidth ? 8 : 6
    }

    private var foregroundOnHover: Color {
        style == .fullWidth ? .white : .black
    }

    private var normalBackground: Color {
        Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.78)
    }

    private var hoverBackground: Color {
        switch style {
        case .compact:
            return .white
        case .fullWidth:
            return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }
}
