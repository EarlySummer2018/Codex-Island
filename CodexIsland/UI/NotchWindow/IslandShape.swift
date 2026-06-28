import CoreGraphics

enum IslandShape: Equatable {
    case compact
    case pill
    case expanded

    static let topInset: CGFloat = 18
    static let fallbackCompactSize = CGSize(width: 120, height: 34)
    static let pillSize = CGSize(width: 440, height: 34)
    static let smallPillSize = CGSize(width: 260, height: 34)
    static let expandedSize = CGSize(width: 440, height: 280)

    static let capsuleCornerRadius: CGFloat = fallbackCompactSize.height / 2
    static let expandedCornerRadius: CGFloat = 28

    func size(
        fitting notchFrame: CGRect,
        capsuleStyle: CapsuleDisplayStyle = .large
    ) -> CGSize {
        switch self {
        case .compact:
            return CGSize(
                width: max(notchFrame.width, Self.fallbackCompactSize.width),
                height: max(notchFrame.height, Self.fallbackCompactSize.height)
            )
        case .pill:
            let pillSize = capsuleStyle.pillSize
            return CGSize(
                width: pillSize.width,
                height: max(notchFrame.height, pillSize.height)
            )
        case .expanded:
            return Self.expandedSize
        }
    }
}
