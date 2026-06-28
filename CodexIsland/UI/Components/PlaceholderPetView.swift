import SwiftUI

struct PlaceholderPetView: View {
    let animation: PetAnimation
    let frame: Int
    let size: CGFloat
    var stage: PetEvolutionStage = .egg
    var prestigeLevel: Int = 0

    var body: some View {
        Canvas { context, canvasSize in
            drawPet(in: context, canvasSize: canvasSize)
        }
        .frame(width: size, height: size)
    }

    private func drawPet(in context: GraphicsContext, canvasSize: CGSize) {
        let pixel = min(canvasSize.width, canvasSize.height) / 24
        let origin = CGPoint(
            x: (canvasSize.width - pixel * 24) / 2 + poseOffset.x * pixel,
            y: (canvasSize.height - pixel * 24) / 2 + poseOffset.y * pixel
        )

        drawAura(in: context, origin: origin, pixel: pixel)
        drawShadow(in: context, origin: origin, pixel: pixel)

        if stage == .egg {
            drawEgg(in: context, origin: origin, pixel: pixel)
            drawStateFeature(in: context, origin: origin, pixel: pixel)
            drawPrestigeSparkles(in: context, origin: origin, pixel: pixel)
            return
        }

        if animation == .errorFall {
            drawFallenPet(in: context, origin: origin, pixel: pixel)
            return
        }

        drawTail(in: context, origin: origin, pixel: pixel)
        drawBackSpikes(in: context, origin: origin, pixel: pixel)
        drawBody(in: context, origin: origin, pixel: pixel)
        drawWing(in: context, origin: origin, pixel: pixel)
        drawHead(in: context, origin: origin, pixel: pixel)
        drawFace(in: context, origin: origin, pixel: pixel)
        drawLegs(in: context, origin: origin, pixel: pixel)
        drawMotionDetails(in: context, origin: origin, pixel: pixel)
        drawStateFeature(in: context, origin: origin, pixel: pixel)
        drawPrestigeSparkles(in: context, origin: origin, pixel: pixel)
    }

    private func drawAura(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        guard animation == .evolveGlow
            || stage.rank >= PetEvolutionStage.guardian.rank
            || prestigeLevel > 0 else {
            return
        }

        let pulse = frame % 4 < 2
        let color = animation == .evolveGlow
            ? tokenSparkColor.opacity(pulse ? 0.62 : 0.34)
            : accentColor.opacity(pulse ? 0.36 : 0.18)

        drawRect(in: context, origin: origin, pixel: pixel, x: 5, y: 4, width: 14, height: 1, color: color)
        drawRect(in: context, origin: origin, pixel: pixel, x: 4, y: 6, width: 1, height: 12, color: color)
        drawRect(in: context, origin: origin, pixel: pixel, x: 19, y: 6, width: 1, height: 12, color: color)
        drawRect(in: context, origin: origin, pixel: pixel, x: 6, y: 20, width: 12, height: 1, color: color)
    }

    private func drawShadow(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let shadowWidth = animation == .awaitJump ? 8 : 12
        let shadowX = animation == .awaitJump ? 8 : 6
        drawRect(
            in: context,
            origin: origin,
            pixel: pixel,
            x: shadowX,
            y: 21,
            width: shadowWidth,
            height: 1,
            color: Color.black.opacity(0.35)
        )
    }

    private func drawTail(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let wag = tailWag
        drawRect(in: context, origin: origin, pixel: pixel, x: 2, y: 12 + wag, width: 3, height: 3, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 4, y: 13 + wag, width: 5, height: 3, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 3, y: 12 + wag, width: 2, height: 2, color: accentColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 5, y: 13 + wag, width: 3, height: 2, color: bodyColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 2, y: 11 + wag, width: 1, height: 1, color: accentColor)

        guard stage.rank >= PetEvolutionStage.guardian.rank else {
            return
        }

        let flameColor = frame % 2 == 0 ? tokenSparkColor : accentColor
        drawRect(in: context, origin: origin, pixel: pixel, x: 0, y: 11 + wag, width: 2, height: 2, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 0, y: 11 + wag, width: 1, height: 1, color: flameColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 1, y: 13 + wag, width: 1, height: 1, color: flameColor.opacity(0.85))
    }

    private func drawBackSpikes(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        guard stage.rank >= PetEvolutionStage.sproutDrake.rank else {
            drawRect(in: context, origin: origin, pixel: pixel, x: 10, y: 9, width: 2, height: 2, color: outline)
            drawRect(in: context, origin: origin, pixel: pixel, x: 10, y: 9, width: 1, height: 1, color: accentColor)
            return
        }

        drawRect(in: context, origin: origin, pixel: pixel, x: 8, y: 9, width: 2, height: 2, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 10, y: 8, width: 2, height: 2, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 13, y: 8, width: 2, height: 2, color: outline)

        drawRect(in: context, origin: origin, pixel: pixel, x: 8, y: 9, width: 1, height: 1, color: accentColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 10, y: 8, width: 1, height: 1, color: accentColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 13, y: 8, width: 1, height: 1, color: accentColor)
    }

    private func drawBody(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let stretch = animation == .idleStretch
        let bodyY = stretch ? 11 : 12
        let bodyHeight = stretch ? 7 : 6

        drawRect(in: context, origin: origin, pixel: pixel, x: 7, y: bodyY, width: 10, height: bodyHeight, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 8, y: bodyY + 1, width: 8, height: bodyHeight - 2, color: bodyColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 10, y: bodyY + 3, width: 5, height: 2, color: bellyColor)

        if animation == .talkWalk {
            drawRect(in: context, origin: origin, pixel: pixel, x: 8, y: bodyY + 1, width: 2, height: 1, color: highlightColor)
        }
    }

    private func drawWing(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let flap = animation == .talkWalk && frame % 4 < 2
        let wingY = flap ? 10 : 11
        let wingHeight = stage.rank >= PetEvolutionStage.glider.rank ? 6 : 5

        drawRect(in: context, origin: origin, pixel: pixel, x: 5, y: wingY, width: 4, height: wingHeight, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 6, y: wingY + 1, width: 2, height: wingHeight - 2, color: wingColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 7, y: wingY + wingHeight - 1, width: 1, height: 1, color: wingColor)

        if stage.rank >= PetEvolutionStage.sproutDrake.rank {
            drawRect(in: context, origin: origin, pixel: pixel, x: 4, y: wingY + 2, width: 2, height: 3, color: outline)
            drawRect(in: context, origin: origin, pixel: pixel, x: 5, y: wingY + 2, width: 1, height: 2, color: wingColor)
        }

        if stage.rank >= PetEvolutionStage.ancient.rank {
            drawRect(in: context, origin: origin, pixel: pixel, x: 3, y: wingY + 3, width: 2, height: 2, color: outline)
            drawRect(in: context, origin: origin, pixel: pixel, x: 3, y: wingY + 3, width: 1, height: 1, color: accentColor)
        }
    }

    private func drawHead(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let nod = animation == .thinkSweat && frame % 4 == 0 ? 1 : 0
        let headY = 5 + nod

        drawRect(in: context, origin: origin, pixel: pixel, x: 10, y: headY, width: 9, height: 8, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 11, y: headY + 1, width: 7, height: 6, color: headColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 17, y: headY + 3, width: 4, height: 4, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 17, y: headY + 4, width: 3, height: 2, color: headColor)

        drawRect(in: context, origin: origin, pixel: pixel, x: 10, y: headY - 2, width: 2, height: 3, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 15, y: headY - 2, width: 2, height: 3, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 10, y: headY - 2, width: 1, height: 2, color: hornColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 16, y: headY - 2, width: 1, height: 2, color: hornColor)

        if stage.rank >= PetEvolutionStage.sproutDrake.rank {
            drawRect(in: context, origin: origin, pixel: pixel, x: 13, y: headY - 3, width: 2, height: 3, color: outline)
            drawRect(in: context, origin: origin, pixel: pixel, x: 13, y: headY - 3, width: 1, height: 2, color: hornColor)
        }

        drawRect(in: context, origin: origin, pixel: pixel, x: 12, y: headY + 1, width: 4, height: 1, color: highlightColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 18, y: headY + 5, width: 2, height: 1, color: noseColor)
    }

    private func drawFace(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let headY = 5 + (animation == .thinkSweat && frame % 4 == 0 ? 1 : 0)
        let blink = animation == .idleBreathe && frame == 6
        let shift = pupilShift

        if blink {
            drawRect(in: context, origin: origin, pixel: pixel, x: 12, y: headY + 3, width: 2, height: 1, color: outline)
            drawRect(in: context, origin: origin, pixel: pixel, x: 16, y: headY + 3, width: 2, height: 1, color: outline)
        } else {
            drawRect(in: context, origin: origin, pixel: pixel, x: 12, y: headY + 2, width: 3, height: 3, color: .white)
            drawRect(in: context, origin: origin, pixel: pixel, x: 16, y: headY + 2, width: 3, height: 3, color: .white)
            drawRect(in: context, origin: origin, pixel: pixel, x: 13 + shift, y: headY + 3, width: 1, height: 1, color: outline)
            drawRect(in: context, origin: origin, pixel: pixel, x: 17 + shift, y: headY + 3, width: 1, height: 1, color: outline)
        }

        switch animation {
        case .talkWalk:
            let open = frame % 2 == 0
            drawRect(in: context, origin: origin, pixel: pixel, x: 17, y: headY + 6, width: 2, height: open ? 2 : 1, color: outline)
            if open {
                drawRect(in: context, origin: origin, pixel: pixel, x: 18, y: headY + 7, width: 1, height: 1, color: mouthColor)
            }
        case .awaitJump:
            drawRect(in: context, origin: origin, pixel: pixel, x: 17, y: headY + 6, width: 2, height: 1, color: outline)
        case .eatToken:
            drawRect(in: context, origin: origin, pixel: pixel, x: 17, y: headY + 6, width: 3, height: 2, color: outline)
            drawRect(in: context, origin: origin, pixel: pixel, x: 18, y: headY + 6, width: 1, height: 1, color: mouthColor)
        default:
            drawRect(in: context, origin: origin, pixel: pixel, x: 18, y: headY + 6, width: 1, height: 1, color: outline)
        }
    }

    private func drawLegs(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let step = animation == .talkWalk && frame % 4 < 2
        drawRect(in: context, origin: origin, pixel: pixel, x: step ? 7 : 8, y: 17, width: 3, height: 3, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: step ? 14 : 13, y: 17, width: 3, height: 3, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: step ? 8 : 9, y: 18, width: 2, height: 1, color: footColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: step ? 15 : 14, y: 18, width: 2, height: 1, color: footColor)
    }

    private func drawMotionDetails(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        if animation == .talkWalk {
            let dustOffset = frame % 4 < 2 ? 0 : 2
            drawRect(in: context, origin: origin, pixel: pixel, x: 4 + dustOffset, y: 20, width: 2, height: 1, color: Color.white.opacity(0.22))
            drawRect(in: context, origin: origin, pixel: pixel, x: 18 - dustOffset, y: 21, width: 2, height: 1, color: Color.white.opacity(0.16))
        }

        if stage.rank >= PetEvolutionStage.ancient.rank && animation == .idleBreathe {
            let shimmerX = frame % 4 < 2 ? 20 : 3
            drawRect(in: context, origin: origin, pixel: pixel, x: shimmerX, y: 9, width: 1, height: 2, color: accentColor.opacity(0.78))
        }
    }

    private func drawStateFeature(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        switch animation {
        case .thinkSweat:
            let sweatY = 4 + (frame % 4)
            drawRect(in: context, origin: origin, pixel: pixel, x: 20, y: sweatY, width: 2, height: 3, color: Color(red: 0.40, green: 0.78, blue: 1.0))
            drawRect(in: context, origin: origin, pixel: pixel, x: 21, y: sweatY + 3, width: 1, height: 1, color: Color(red: 0.40, green: 0.78, blue: 1.0))
        case .awaitJump:
            let flash = frame % 4 < 2
            drawRect(in: context, origin: origin, pixel: pixel, x: 20, y: 3, width: 1, height: 4, color: flash ? hornColor : .white)
            drawRect(in: context, origin: origin, pixel: pixel, x: 20, y: 8, width: 1, height: 1, color: flash ? hornColor : .white)
        case .eatToken:
            let tokenX = max(14, 22 - frame)
            drawRect(in: context, origin: origin, pixel: pixel, x: tokenX, y: 11, width: 4, height: 4, color: outline)
            drawRect(in: context, origin: origin, pixel: pixel, x: tokenX + 1, y: 12, width: 2, height: 2, color: tokenColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: tokenX + 2, y: 11, width: 1, height: 4, color: tokenSparkColor)
        case .evolveGlow:
            let glow = frame % 2 == 0
            let sparkleColor = glow ? tokenSparkColor : accentColor
            drawRect(in: context, origin: origin, pixel: pixel, x: 4, y: 5, width: 2, height: 2, color: sparkleColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: 19, y: 4, width: 2, height: 2, color: sparkleColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: 3, y: 18, width: 2, height: 2, color: sparkleColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: 21, y: 17, width: 1, height: 3, color: sparkleColor)
        default:
            break
        }
    }

    private func drawPrestigeSparkles(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        guard prestigeLevel > 0 else {
            return
        }

        let sparkleCount = min(prestigeLevel, 3)
        let points = [
            (x: 3, y: 6 + frame % 2),
            (x: 20, y: 7 + (frame + 1) % 2),
            (x: 5, y: 18 - frame % 2)
        ]

        for index in 0..<sparkleCount {
            let point = points[index]
            drawRect(in: context, origin: origin, pixel: pixel, x: point.x, y: point.y, width: 2, height: 1, color: tokenSparkColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: point.x + 1, y: point.y - 1, width: 1, height: 3, color: tokenSparkColor.opacity(0.86))
        }
    }

    private func drawEgg(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let bob = frame % 4 < 2 ? 0 : 1
        drawRect(in: context, origin: origin, pixel: pixel, x: 8, y: 8 + bob, width: 9, height: 12, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 9, y: 7 + bob, width: 7, height: 2, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 9, y: 9 + bob, width: 7, height: 10, color: Color(red: 0.88, green: 0.98, blue: 0.86))
        drawRect(in: context, origin: origin, pixel: pixel, x: 10, y: 8 + bob, width: 5, height: 1, color: Color(red: 0.96, green: 1.0, blue: 0.92))
        drawRect(in: context, origin: origin, pixel: pixel, x: 10, y: 12 + bob, width: 2, height: 2, color: accentColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 13, y: 15 + bob, width: 2, height: 2, color: bodyColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 12, y: 10 + bob, width: 1, height: 1, color: bodyColor)
    }

    private func drawFallenPet(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let slide = min(frame, 6) / 2

        drawShadow(in: context, origin: origin, pixel: pixel)
        drawRect(in: context, origin: origin, pixel: pixel, x: 5 + slide, y: 14, width: 13, height: 5, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 6 + slide, y: 15, width: 11, height: 3, color: mutedBodyColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 12 + slide, y: 10, width: 8, height: 5, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 13 + slide, y: 11, width: 6, height: 3, color: mutedHeadColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 14 + slide, y: 12, width: 2, height: 1, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 17 + slide, y: 12, width: 2, height: 1, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 3 + slide, y: 15, width: 4, height: 2, color: outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 3 + slide, y: 15, width: 2, height: 1, color: hornColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 7, y: 7, width: 2, height: 2, color: tokenColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 20, y: 8, width: 2, height: 2, color: tokenColor)
    }

    private func drawRect(
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

    private var poseOffset: CGPoint {
        switch animation {
        case .idleBreathe:
            return CGPoint(x: 0, y: frame % 4 < 2 ? -1 : 0)
        case .idleStretch:
            return CGPoint(x: 0, y: frame % 6 < 3 ? -1 : 0)
        case .thinkSweat:
            return CGPoint(x: frame % 4 == 0 ? -1 : 0, y: 0)
        case .talkWalk:
            return CGPoint(x: frame % 4 < 2 ? -1 : 1, y: frame % 2 == 0 ? -1 : 0)
        case .awaitJump:
            return CGPoint(x: 0, y: frame < 5 ? -3 : -1)
        case .eatToken, .evolveGlow:
            return CGPoint(x: frame % 2 == 0 ? 0 : 1, y: 0)
        case .errorFall:
            return .zero
        }
    }

    private var tailWag: Int {
        switch animation {
        case .talkWalk, .awaitJump:
            return frame % 4 < 2 ? -1 : 1
        case .eatToken, .evolveGlow:
            return frame % 2 == 0 ? 0 : -1
        default:
            return frame % 6 < 3 ? 0 : 1
        }
    }

    private var pupilShift: Int {
        switch animation {
        case .thinkSweat:
            return frame % 4 == 0 ? -1 : 0
        case .talkWalk, .eatToken, .evolveGlow:
            return 1
        default:
            return 0
        }
    }

    private var outline: Color {
        Color(red: 0.04, green: 0.07, blue: 0.07)
    }

    private var headColor: Color {
        if animation == .evolveGlow {
            return tokenSparkColor
        }

        switch animation {
        case .thinkSweat:
            return Color(red: 0.90, green: 0.80, blue: 0.34)
        case .awaitJump:
            return Color(red: 0.94, green: 0.35, blue: 0.54)
        case .errorFall:
            return mutedHeadColor
        default:
            return stage.headColor
        }
    }

    private var bodyColor: Color {
        if animation == .evolveGlow {
            return accentColor
        }

        switch animation {
        case .thinkSweat:
            return Color(red: 0.80, green: 0.70, blue: 0.25)
        case .awaitJump:
            return Color(red: 0.84, green: 0.25, blue: 0.45)
        case .errorFall:
            return mutedBodyColor
        default:
            return stage.bodyColor
        }
    }

    private var bellyColor: Color {
        Color(red: 0.78, green: 0.98, blue: 0.72)
    }

    private var accentColor: Color {
        stage.accentColor
    }

    private var hornColor: Color {
        stage.rank >= PetEvolutionStage.guardian.rank
            ? Color(red: 0.68, green: 0.88, blue: 1.0)
            : Color(red: 1.0, green: 0.86, blue: 0.28)
    }

    private var wingColor: Color {
        stage.rank >= PetEvolutionStage.glider.rank
            ? Color(red: 0.18, green: 0.38, blue: 0.72)
            : Color(red: 0.14, green: 0.45, blue: 0.46)
    }

    private var highlightColor: Color {
        Color.white.opacity(0.42)
    }

    private var footColor: Color {
        Color(red: 0.03, green: 0.18, blue: 0.16)
    }

    private var noseColor: Color {
        Color(red: 0.02, green: 0.18, blue: 0.17)
    }

    private var mouthColor: Color {
        Color(red: 1.0, green: 0.47, blue: 0.55)
    }

    private var tokenColor: Color {
        Color(red: 0.98, green: 0.76, blue: 0.18)
    }

    private var tokenSparkColor: Color {
        Color(red: 1.0, green: 0.96, blue: 0.58)
    }

    private var mutedHeadColor: Color {
        Color(red: 0.48, green: 0.62, blue: 0.61)
    }

    private var mutedBodyColor: Color {
        Color(red: 0.34, green: 0.45, blue: 0.45)
    }
}

private extension PetEvolutionStage {
    var headColor: Color {
        switch self {
        case .egg:
            return Color(red: 0.88, green: 0.98, blue: 0.86)
        case .hatchling:
            return Color(red: 0.25, green: 0.86, blue: 0.70)
        case .sproutDrake:
            return Color(red: 0.20, green: 0.86, blue: 0.67)
        case .glider:
            return Color(red: 0.28, green: 0.74, blue: 0.95)
        case .guardian:
            return Color(red: 0.45, green: 0.82, blue: 1.0)
        case .ancient:
            return Color(red: 0.66, green: 0.72, blue: 1.0)
        }
    }

    var bodyColor: Color {
        switch self {
        case .egg:
            return Color(red: 0.70, green: 0.90, blue: 0.70)
        case .hatchling:
            return Color(red: 0.10, green: 0.68, blue: 0.56)
        case .sproutDrake:
            return Color(red: 0.08, green: 0.70, blue: 0.58)
        case .glider:
            return Color(red: 0.08, green: 0.55, blue: 0.76)
        case .guardian:
            return Color(red: 0.16, green: 0.42, blue: 0.86)
        case .ancient:
            return Color(red: 0.30, green: 0.36, blue: 0.82)
        }
    }

    var accentColor: Color {
        switch self {
        case .egg, .hatchling, .sproutDrake:
            return Color(red: 0.95, green: 0.88, blue: 0.28)
        case .glider:
            return Color(red: 0.42, green: 0.94, blue: 1.0)
        case .guardian:
            return Color(red: 1.0, green: 0.70, blue: 0.24)
        case .ancient:
            return Color(red: 0.90, green: 0.72, blue: 1.0)
        }
    }
}
