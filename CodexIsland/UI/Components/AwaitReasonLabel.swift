import SwiftUI

struct AwaitReasonLabel: View {
    let reason: AwaitReason?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(iconColor.opacity(0.9))

            Text(labelText)
                .font(.system(size: 9, weight: .regular, design: textDesign))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var iconName: String {
        switch reason {
        case .toolApproval:
            return "terminal.fill"
        case .question:
            return "questionmark.circle.fill"
        case nil:
            return "exclamationmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch reason {
        case .toolApproval:
            return TokenColors.output
        case .question:
            return TokenColors.input
        case nil:
            return TokenColors.uncached
        }
    }

    private var textDesign: Font.Design {
        switch reason {
        case .toolApproval:
            return .monospaced
        case .question, nil:
            return .rounded
        }
    }

    private var labelText: String {
        guard let reason else {
            return "需要您的输入"
        }

        switch reason {
        case .toolApproval(let tool, let command):
            guard let command, !command.isEmpty else {
                return "审批 \(tool)"
            }

            return "\(tool): \(truncated(command, limit: 30))"

        case .question(let text):
            guard let text, !text.isEmpty else {
                return "需要您的回答"
            }

            return truncated(text, limit: 40)
        }
    }

    private func truncated(_ text: String, limit: Int) -> String {
        if text.count <= limit {
            return text
        }

        return "\(text.prefix(limit))..."
    }
}
