import SwiftUI

struct PixelLevelBadgeView: View {
    let level: Int
    let levelUpTrigger: UUID?

    @State private var isCelebrating = false
    @State private var celebrationWorkItem: DispatchWorkItem?

    var body: some View {
        Canvas { context, size in
            PixelLevelBadgeRenderer.draw(
                level: level,
                isCelebrating: isCelebrating,
                in: context,
                size: size
            )
        }
        .frame(
            width: PixelLevelBadgeRenderer.canvasSize(for: level).width,
            height: PixelLevelBadgeRenderer.canvasSize(for: level).height
        )
        .scaleEffect(isCelebrating ? 1.18 : 1.0)
        .offset(y: isCelebrating ? -5 : 0)
        .shadow(
            color: Color(red: 1.0, green: 0.83, blue: 0.25).opacity(isCelebrating ? 0.75 : 0.25),
            radius: isCelebrating ? 8 : 3,
            x: 0,
            y: isCelebrating ? 0 : 2
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.58), value: isCelebrating)
        .onChange(of: levelUpTrigger) { trigger in
            guard trigger != nil else {
                return
            }

            playCelebration()
        }
        .onDisappear {
            celebrationWorkItem?.cancel()
            celebrationWorkItem = nil
        }
        .accessibilityLabel("Pet level \(PetLevelCurve.clamp(level))")
    }

    private func playCelebration() {
        celebrationWorkItem?.cancel()
        isCelebrating = true
        let workItem = DispatchWorkItem {
            isCelebrating = false
        }
        celebrationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: workItem)
    }
}

enum PixelLevelBadgeText {
    static func text(for level: Int) -> String {
        "LV.\(PetLevelCurve.clamp(level))"
    }
}

struct PixelLevelBadgePixel: Equatable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

enum PixelLevelBadgeRenderer {
    private static let unit: CGFloat = 2
    private static let glyphHeight = 5
    private static let horizontalPadding = 2
    private static let verticalPadding = 1
    private static let glyphGap = 1

    static func canvasSize(for level: Int) -> CGSize {
        let text = PixelLevelBadgeText.text(for: level)
        let widthUnits = textWidthUnits(for: text) + horizontalPadding * 2
        let heightUnits = glyphHeight + verticalPadding * 2

        return CGSize(
            width: CGFloat(widthUnits) * unit,
            height: CGFloat(heightUnits) * unit
        )
    }

    static func pixelRuns(for text: String) -> [PixelLevelBadgePixel] {
        var runs: [PixelLevelBadgePixel] = []
        var cursorX = 0

        for character in text {
            let glyphRuns = glyph(for: character)
            runs.append(
                contentsOf: glyphRuns.map { run in
                    PixelLevelBadgePixel(
                        x: run.x + cursorX,
                        y: run.y,
                        width: run.width,
                        height: run.height
                    )
                }
            )
            cursorX += glyphWidth(for: character) + glyphGap
        }

        return runs
    }

    static func draw(
        level: Int,
        isCelebrating: Bool,
        in context: GraphicsContext,
        size: CGSize
    ) {
        let text = PixelLevelBadgeText.text(for: level)
        let widthUnits = textWidthUnits(for: text) + horizontalPadding * 2
        let heightUnits = glyphHeight + verticalPadding * 2
        let pixel = min(size.width / CGFloat(widthUnits), size.height / CGFloat(heightUnits))
        let origin = CGPoint(
            x: (size.width - CGFloat(widthUnits) * pixel) / 2,
            y: (size.height - CGFloat(heightUnits) * pixel) / 2
        )

        drawBadgeBackground(
            in: context,
            origin: origin,
            pixel: pixel,
            widthUnits: widthUnits,
            heightUnits: heightUnits,
            isCelebrating: isCelebrating
        )

        let textOrigin = CGPoint(
            x: origin.x + CGFloat(horizontalPadding) * pixel,
            y: origin.y + CGFloat(verticalPadding) * pixel
        )
        let textColor = isCelebrating
            ? Color(red: 1.0, green: 0.95, blue: 0.60)
            : Color(red: 0.62, green: 0.97, blue: 1.0)

        for run in pixelRuns(for: text) {
            drawRect(
                in: context,
                origin: textOrigin,
                pixel: pixel,
                x: run.x,
                y: run.y,
                width: run.width,
                height: run.height,
                color: textColor
            )
        }

        if isCelebrating {
            drawSparkles(
                in: context,
                origin: origin,
                pixel: pixel,
                widthUnits: widthUnits,
                heightUnits: heightUnits
            )
        }
    }

    private static func drawBadgeBackground(
        in context: GraphicsContext,
        origin: CGPoint,
        pixel: CGFloat,
        widthUnits: Int,
        heightUnits: Int,
        isCelebrating: Bool
    ) {
        let outline = Color(red: 0.03, green: 0.05, blue: 0.10)
        let fill = isCelebrating
            ? Color(red: 0.35, green: 0.24, blue: 0.08)
            : Color(red: 0.05, green: 0.13, blue: 0.25)
        let rim = isCelebrating
            ? Color(red: 1.0, green: 0.76, blue: 0.20)
            : Color(red: 0.22, green: 0.45, blue: 0.82)

        drawRect(in: context, origin: origin, pixel: pixel, x: 1, y: 0, width: widthUnits - 2, height: heightUnits, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 0, y: 1, width: widthUnits, height: heightUnits - 2, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 1, y: 1, width: widthUnits - 2, height: heightUnits - 2, color: fill)
        drawRect(in: context, origin: origin, pixel: pixel, x: 2, y: 1, width: widthUnits - 4, height: 1, color: rim.opacity(0.86))
        drawRect(in: context, origin: origin, pixel: pixel, x: 2, y: heightUnits - 2, width: widthUnits - 4, height: 1, color: rim.opacity(0.50))
    }

    private static func drawSparkles(
        in context: GraphicsContext,
        origin: CGPoint,
        pixel: CGFloat,
        widthUnits: Int,
        heightUnits: Int
    ) {
        let sparkle = Color(red: 1.0, green: 0.92, blue: 0.38)
        let points = [
            PixelLevelBadgePixel(x: 0, y: 0, width: 1, height: 1),
            PixelLevelBadgePixel(x: widthUnits - 1, y: 0, width: 1, height: 1),
            PixelLevelBadgePixel(x: 1, y: heightUnits - 1, width: 1, height: 1),
            PixelLevelBadgePixel(x: widthUnits - 2, y: heightUnits - 1, width: 1, height: 1)
        ]

        for point in points {
            drawRect(
                in: context,
                origin: origin,
                pixel: pixel,
                x: point.x,
                y: point.y,
                width: point.width,
                height: point.height,
                color: sparkle
            )
        }
    }

    private static func textWidthUnits(for text: String) -> Int {
        guard !text.isEmpty else {
            return 0
        }

        let glyphWidths = text.map(glyphWidth(for:)).reduce(0, +)
        return glyphWidths + max(text.count - 1, 0) * glyphGap
    }

    private static func glyphWidth(for character: Character) -> Int {
        character == "." ? 1 : 3
    }

    private static func glyph(for character: Character) -> [PixelLevelBadgePixel] {
        switch character {
        case "L":
            return runs(
                "100",
                "100",
                "100",
                "100",
                "111"
            )
        case "V":
            return runs(
                "101",
                "101",
                "101",
                "101",
                "010"
            )
        case ".":
            return [PixelLevelBadgePixel(x: 0, y: 4, width: 1, height: 1)]
        case "0":
            return runs(
                "111",
                "101",
                "101",
                "101",
                "111"
            )
        case "1":
            return runs(
                "010",
                "110",
                "010",
                "010",
                "111"
            )
        case "2":
            return runs(
                "111",
                "001",
                "111",
                "100",
                "111"
            )
        case "3":
            return runs(
                "111",
                "001",
                "111",
                "001",
                "111"
            )
        case "4":
            return runs(
                "101",
                "101",
                "111",
                "001",
                "001"
            )
        case "5":
            return runs(
                "111",
                "100",
                "111",
                "001",
                "111"
            )
        case "6":
            return runs(
                "111",
                "100",
                "111",
                "101",
                "111"
            )
        case "7":
            return runs(
                "111",
                "001",
                "010",
                "010",
                "010"
            )
        case "8":
            return runs(
                "111",
                "101",
                "111",
                "101",
                "111"
            )
        case "9":
            return runs(
                "111",
                "101",
                "111",
                "001",
                "111"
            )
        default:
            return []
        }
    }

    private static func runs(_ rows: String...) -> [PixelLevelBadgePixel] {
        var pixels: [PixelLevelBadgePixel] = []

        for (y, row) in rows.enumerated() {
            for (x, value) in row.enumerated() where value == "1" {
                pixels.append(PixelLevelBadgePixel(x: x, y: y, width: 1, height: 1))
            }
        }

        return pixels
    }

    private static func drawRect(
        in context: GraphicsContext,
        origin: CGPoint,
        pixel: CGFloat,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        color: Color
    ) {
        var path = Path()
        path.addRect(
            CGRect(
                x: origin.x + CGFloat(x) * pixel,
                y: origin.y + CGFloat(y) * pixel,
                width: CGFloat(width) * pixel,
                height: CGFloat(height) * pixel
            )
        )
        context.fill(path, with: .color(color))
    }
}
