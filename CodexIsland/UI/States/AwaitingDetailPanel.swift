import SwiftUI

struct AwaitingDetailPanel: View {
    let reason: AwaitReason?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Codex 需要您的确认", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.94, green: 0.27, blue: 0.27))
                .lineLimit(1)

            reasonContent

            ActivateCodexButton(title: "前往 Codex 回复", style: .fullWidth)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.075))
    }

    @ViewBuilder
    private var reasonContent: some View {
        switch reason {
        case .toolApproval(let tool, let command):
            VStack(alignment: .leading, spacing: 4) {
                Text("工具：\(tool)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                if let command, !command.isEmpty {
                    Text(command)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(TokenColors.output)
                        .lineLimit(4)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }

        case .question(let text):
            Text(text?.isEmpty == false ? text! : "需要您的回答")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

        case nil:
            Text("Codex 暂停中，正在等待您的输入。")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(2)
        }
    }
}
