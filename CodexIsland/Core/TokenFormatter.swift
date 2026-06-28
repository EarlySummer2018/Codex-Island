import Foundation

enum TokenFormatter {
    static func format(_ count: Int) -> String {
        switch count {
        case 0..<1_000:
            return "\(count)"
        case 1_000..<10_000:
            let value = Double(count) / 1_000
            return String(format: "%.1fK", value)
        case 10_000..<1_000_000:
            return "\(count / 1_000)K"
        default:
            let value = Double(count) / 1_000_000
            return String(format: "%.1fM", value)
        }
    }

    static func formatDelta(_ count: Int) -> String {
        guard count > 0 else {
            return "0"
        }

        return "+\(format(count))"
    }

    static func formatSaving(cached: Int, total: Int) -> String {
        guard total > 0 else {
            return "0%"
        }

        let rate = Double(cached) / Double(total) * 100
        return String(format: "%.0f%%", rate)
    }
}
