import SwiftUI

struct PlaceholderPetView: View {
    let animation: PetAnimation
    let frame: Int
    let size: CGFloat
    var form: PetForm = .core
    var level: Int = 0

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

        if animation == .errorFall {
            drawFallenPet(in: context, origin: origin, pixel: pixel)
            drawPrestigeSparkles(in: context, origin: origin, pixel: pixel)
            return
        }

        drawEvolutionModules(in: context, origin: origin, pixel: pixel)
        drawBackFins(in: context, origin: origin, pixel: pixel)
        drawArms(in: context, origin: origin, pixel: pixel)
        drawBody(in: context, origin: origin, pixel: pixel)
        drawCoreMarkings(in: context, origin: origin, pixel: pixel)
        drawFacePlate(in: context, origin: origin, pixel: pixel)
        drawFace(in: context, origin: origin, pixel: pixel)
        drawFeet(in: context, origin: origin, pixel: pixel)
        drawMotionDetails(in: context, origin: origin, pixel: pixel)
        drawStateFeature(in: context, origin: origin, pixel: pixel)
        drawPrestigeSparkles(in: context, origin: origin, pixel: pixel)
    }

    private func drawAura(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        guard animation == .evolveGlow
            || animation == .celebrateDance
            || animation == .maxVictory
            || level >= 70
            || form.rank >= PetForm.shield.rank else {
            return
        }

        let pulse = frame % 4 < 2
        let auraColor = animation == .evolveGlow
            ? palette.spark.opacity(pulse ? 0.68 : 0.34)
            : palette.accent.opacity(pulse ? 0.38 : 0.18)

        drawRect(in: context, origin: origin, pixel: pixel, x: 6, y: 3, width: 12, height: 1, color: auraColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 4, y: 6, width: 1, height: 12, color: auraColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 19, y: 6, width: 1, height: 12, color: auraColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 7, y: 21, width: 10, height: 1, color: auraColor)
    }

    private func drawShadow(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let shadowWidth = animation == .awaitJump ? 8 : 12
        let shadowX = animation == .awaitJump ? 8 : 6
        let opacity = animation == .awaitJump ? 0.22 : 0.36

        drawRect(
            in: context,
            origin: origin,
            pixel: pixel,
            x: shadowX,
            y: 21,
            width: shadowWidth,
            height: 1,
            color: Color.black.opacity(opacity)
        )
    }

    private func drawEvolutionModules(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        guard form.rank > PetForm.core.rank else {
            return
        }

        let antennaTilt = frame % 6 < 3 ? 0 : 1
        drawRect(in: context, origin: origin, pixel: pixel, x: 11, y: 2, width: 2, height: 3, color: palette.outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 12, y: 2, width: 1, height: 3, color: palette.accent)

        if form.rank >= PetForm.antenna.rank {
            drawRect(in: context, origin: origin, pixel: pixel, x: 13 + antennaTilt, y: 1, width: 3, height: 2, color: palette.outline)
            drawRect(in: context, origin: origin, pixel: pixel, x: 13 + antennaTilt, y: 1, width: 2, height: 1, color: palette.leaf)
            drawRect(in: context, origin: origin, pixel: pixel, x: 9 - antennaTilt, y: 1, width: 3, height: 2, color: palette.outline)
            drawRect(in: context, origin: origin, pixel: pixel, x: 10 - antennaTilt, y: 1, width: 2, height: 1, color: palette.leaf)
        }

        if form.rank >= PetForm.spark.rank {
            drawRect(in: context, origin: origin, pixel: pixel, x: 11, y: 0, width: 2, height: 3, color: palette.warning)
            drawRect(in: context, origin: origin, pixel: pixel, x: 12, y: 2, width: 2, height: 2, color: palette.spark)
        }

        if form.rank >= PetForm.spirit.rank {
            drawRect(in: context, origin: origin, pixel: pixel, x: 7, y: 2, width: 2, height: 1, color: palette.accent)
            drawRect(in: context, origin: origin, pixel: pixel, x: 16, y: 2, width: 2, height: 1, color: palette.accent)
        }
    }

    private func drawCoreMarkings(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        if form.rank >= PetForm.ripple.rank {
            drawRect(in: context, origin: origin, pixel: pixel, x: 6, y: 10, width: 2, height: 1, color: palette.accent.opacity(0.78))
            drawRect(in: context, origin: origin, pixel: pixel, x: 16, y: 10, width: 2, height: 1, color: palette.accent.opacity(0.78))
            drawRect(in: context, origin: origin, pixel: pixel, x: 7, y: 16, width: 3, height: 1, color: palette.rimLight.opacity(0.70))
            drawRect(in: context, origin: origin, pixel: pixel, x: 14, y: 16, width: 3, height: 1, color: palette.rimLight.opacity(0.70))
        }

        if form.rank >= PetForm.shell.rank {
            drawRect(in: context, origin: origin, pixel: pixel, x: 5, y: 7, width: 3, height: 2, color: palette.shell)
            drawRect(in: context, origin: origin, pixel: pixel, x: 16, y: 7, width: 3, height: 2, color: palette.shell)
            drawRect(in: context, origin: origin, pixel: pixel, x: 6, y: 15, width: 2, height: 2, color: palette.shell.opacity(0.88))
            drawRect(in: context, origin: origin, pixel: pixel, x: 16, y: 15, width: 2, height: 2, color: palette.shell.opacity(0.88))
        }

        if form.rank >= PetForm.shield.rank {
            drawRect(in: context, origin: origin, pixel: pixel, x: 4, y: 11, width: 2, height: 6, color: palette.shield.opacity(0.72))
            drawRect(in: context, origin: origin, pixel: pixel, x: 18, y: 11, width: 2, height: 6, color: palette.shield.opacity(0.72))
        }

        if form.rank >= PetForm.crystal.rank {
            drawRect(in: context, origin: origin, pixel: pixel, x: 6, y: 5, width: 2, height: 2, color: palette.crystal)
            drawRect(in: context, origin: origin, pixel: pixel, x: 17, y: 5, width: 2, height: 2, color: palette.crystal)
            drawRect(in: context, origin: origin, pixel: pixel, x: 11, y: 17, width: 3, height: 1, color: palette.crystal.opacity(0.88))
        }

        if form.rank >= PetForm.star.rank {
            drawRect(in: context, origin: origin, pixel: pixel, x: 3, y: 8, width: 1, height: 2, color: palette.star)
            drawRect(in: context, origin: origin, pixel: pixel, x: 20, y: 8, width: 1, height: 2, color: palette.star)
            drawRect(in: context, origin: origin, pixel: pixel, x: 11, y: 3, width: 3, height: 1, color: palette.star.opacity(0.82))
        }
    }

    private func drawBackFins(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        guard form.rank >= PetForm.glider.rank else {
            return
        }

        let flap = animation == .talkWalk && frame % 4 < 2
        let y = flap ? 10 : 11

        drawRect(in: context, origin: origin, pixel: pixel, x: 3, y: y + 1, width: 4, height: 5, color: palette.outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 4, y: y + 2, width: 2, height: 3, color: palette.fin)
        drawRect(in: context, origin: origin, pixel: pixel, x: 18, y: y + 1, width: 3, height: 5, color: palette.outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 18, y: y + 2, width: 2, height: 3, color: palette.fin)

        if form.rank >= PetForm.star.rank {
            drawRect(in: context, origin: origin, pixel: pixel, x: 2, y: y + 3, width: 2, height: 2, color: palette.accent)
            drawRect(in: context, origin: origin, pixel: pixel, x: 20, y: y + 3, width: 2, height: 2, color: palette.accent)
        }
    }

    private func drawArms(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let walk = animation == .talkWalk && frame % 4 < 2
        let leftY = walk ? 13 : 14
        let rightY = walk ? 15 : 14

        drawRect(in: context, origin: origin, pixel: pixel, x: 4, y: leftY, width: 3, height: 4, color: palette.outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 5, y: leftY + 1, width: 1, height: 2, color: bodyShadowColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 17, y: rightY, width: 3, height: 4, color: palette.outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 18, y: rightY + 1, width: 1, height: 2, color: bodyShadowColor)
    }

    private func drawBody(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let stretch = animation == .idleStretch
        let squash = stretch && frame > 5
        let yShift = stretch && frame <= 5 ? -1 : 0
        let xInset = squash ? 1 : 0

        let outlineRows = [
            PixelRun(x: 9 + xInset, y: 4 + yShift, width: 6 - xInset * 2),
            PixelRun(x: 7 + xInset, y: 5 + yShift, width: 10 - xInset * 2),
            PixelRun(x: 6 + xInset, y: 6 + yShift, width: 12 - xInset * 2),
            PixelRun(x: 5 + xInset, y: 7 + yShift, width: 14 - xInset * 2),
            PixelRun(x: 4 + xInset, y: 8 + yShift, width: 16 - xInset * 2),
            PixelRun(x: 4 + xInset, y: 9 + yShift, width: 16 - xInset * 2),
            PixelRun(x: 4 + xInset, y: 10 + yShift, width: 16 - xInset * 2),
            PixelRun(x: 5 + xInset, y: 11 + yShift, width: 14 - xInset * 2),
            PixelRun(x: 5 + xInset, y: 12 + yShift, width: 14 - xInset * 2),
            PixelRun(x: 6 + xInset, y: 13 + yShift, width: 12 - xInset * 2),
            PixelRun(x: 6 + xInset, y: 14 + yShift, width: 12 - xInset * 2),
            PixelRun(x: 7 + xInset, y: 15 + yShift, width: 10 - xInset * 2),
            PixelRun(x: 7 + xInset, y: 16 + yShift, width: 10 - xInset * 2),
            PixelRun(x: 8 + xInset, y: 17 + yShift, width: 8 - xInset * 2),
            PixelRun(x: 9 + xInset, y: 18 + yShift, width: 6 - xInset * 2)
        ]

        drawRuns(outlineRows, in: context, origin: origin, pixel: pixel, color: palette.outline)

        let fillRows = outlineRows.compactMap { row -> PixelRun? in
            guard row.width > 2 else {
                return nil
            }

            return PixelRun(x: row.x + 1, y: row.y, width: row.width - 2)
        }
        drawRuns(fillRows, in: context, origin: origin, pixel: pixel, color: bodyColor)

        drawRect(in: context, origin: origin, pixel: pixel, x: 7 + xInset, y: 12 + yShift, width: 10 - xInset * 2, height: 4, color: bodyShadowColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 8 + xInset, y: 13 + yShift, width: 8 - xInset * 2, height: 3, color: bellyColor)

        drawRect(in: context, origin: origin, pixel: pixel, x: 8 + xInset, y: 5 + yShift, width: 4, height: 1, color: palette.highlight)
        drawRect(in: context, origin: origin, pixel: pixel, x: 6 + xInset, y: 8 + yShift, width: 2, height: 2, color: palette.rimLight)
        drawRect(in: context, origin: origin, pixel: pixel, x: 14 - xInset, y: 5 + yShift, width: 2, height: 1, color: palette.rimLight.opacity(0.82))
    }

    private func drawFacePlate(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let blinkOffset = animation == .thinkSweat && frame % 4 == 0 ? 1 : 0
        let y = 8 + blinkOffset

        let outlineRows = [
            PixelRun(x: 8, y: y, width: 8),
            PixelRun(x: 7, y: y + 1, width: 10),
            PixelRun(x: 7, y: y + 2, width: 10),
            PixelRun(x: 7, y: y + 3, width: 10),
            PixelRun(x: 7, y: y + 4, width: 10),
            PixelRun(x: 8, y: y + 5, width: 8)
        ]
        let fillRows = [
            PixelRun(x: 8, y: y + 1, width: 8),
            PixelRun(x: 8, y: y + 2, width: 8),
            PixelRun(x: 8, y: y + 3, width: 8),
            PixelRun(x: 8, y: y + 4, width: 8)
        ]

        drawRuns(outlineRows, in: context, origin: origin, pixel: pixel, color: palette.screenOutline)
        drawRuns(fillRows, in: context, origin: origin, pixel: pixel, color: screenColor)
        drawRect(in: context, origin: origin, pixel: pixel, x: 9, y: y + 1, width: 3, height: 1, color: palette.screenGlint.opacity(0.36))
    }

    private func drawFace(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let y = 8 + (animation == .thinkSweat && frame % 4 == 0 ? 1 : 0)
        let blink = animation == .idleBreathe && frame == 6
        let glyphColor = faceGlyphColor
        let shift = pupilShift

        if blink {
            drawRect(in: context, origin: origin, pixel: pixel, x: 9, y: y + 3, width: 2, height: 1, color: glyphColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: 13, y: y + 3, width: 2, height: 1, color: glyphColor)
            return
        }

        switch animation {
        case .errorFall:
            break
        case .talkWalk, .outputBurst:
            drawPromptGlyph(in: context, origin: origin, pixel: pixel, x: 9 + shift, y: y + 2, color: glyphColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: 13, y: y + 2, width: 2, height: 1, color: glyphColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: 12, y: y + 4, width: frame % 2 == 0 ? 3 : 2, height: 1, color: glyphColor)
        case .awaitJump, .shieldWait:
            drawRect(in: context, origin: origin, pixel: pixel, x: 9, y: y + 2, width: 2, height: 2, color: palette.warning)
            drawRect(in: context, origin: origin, pixel: pixel, x: 14, y: y + 2, width: 1, height: 3, color: palette.warning)
            drawRect(in: context, origin: origin, pixel: pixel, x: 12, y: y + 4, width: 3, height: 1, color: palette.warning)
        case .eatToken, .tokenOrbit:
            drawPromptGlyph(in: context, origin: origin, pixel: pixel, x: 9 + shift, y: y + 2, color: glyphColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: 13, y: y + 2, width: 2, height: 1, color: glyphColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: 12, y: y + 4, width: 3, height: 1, color: palette.mouth)
        default:
            drawPromptGlyph(in: context, origin: origin, pixel: pixel, x: 9 + shift, y: y + 2, color: glyphColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: 14 + shift, y: y + 2, width: 2, height: 1, color: glyphColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: 12, y: y + 4, width: 2, height: 1, color: glyphColor.opacity(0.82))
        }
    }

    private func drawPromptGlyph(
        in context: GraphicsContext,
        origin: CGPoint,
        pixel: CGFloat,
        x: Int,
        y: Int,
        color: Color
    ) {
        drawRect(in: context, origin: origin, pixel: pixel, x: x, y: y, width: 1, height: 1, color: color)
        drawRect(in: context, origin: origin, pixel: pixel, x: x + 1, y: y + 1, width: 1, height: 1, color: color)
        drawRect(in: context, origin: origin, pixel: pixel, x: x, y: y + 2, width: 1, height: 1, color: color)
    }

    private func drawFeet(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let step = (animation == .talkWalk || animation == .outputBurst) && frame % 4 < 2
        let leftY = step ? 19 : 18
        let rightY = step ? 18 : 19

        drawRect(in: context, origin: origin, pixel: pixel, x: step ? 7 : 8, y: leftY, width: 4, height: 3, color: palette.outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: step ? 8 : 9, y: leftY, width: 2, height: 2, color: palette.foot)
        drawRect(in: context, origin: origin, pixel: pixel, x: step ? 14 : 13, y: rightY, width: 4, height: 3, color: palette.outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: step ? 15 : 14, y: rightY, width: 2, height: 2, color: palette.foot)
    }

    private func drawMotionDetails(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        if animation == .talkWalk || animation == .outputBurst {
            let dustOffset = frame % 4 < 2 ? 0 : 2
            drawRect(in: context, origin: origin, pixel: pixel, x: 4 + dustOffset, y: 20, width: 2, height: 1, color: Color.white.opacity(0.22))
            drawRect(in: context, origin: origin, pixel: pixel, x: 18 - dustOffset, y: 21, width: 2, height: 1, color: Color.white.opacity(0.16))
        }

        if form.rank >= PetForm.star.rank && (animation == .idleBreathe || animation == .spiritIdle) {
            let shimmerX = frame % 4 < 2 ? 20 : 3
            drawRect(in: context, origin: origin, pixel: pixel, x: shimmerX, y: 9, width: 1, height: 2, color: palette.accent.opacity(0.78))
        }
    }

    private func drawStateFeature(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        switch animation {
        case .thinkSweat, .bubbleThink:
            let sweatY = 4 + (frame % 4)
            let color = animation == .bubbleThink ? palette.accent : palette.sweat
            drawRect(in: context, origin: origin, pixel: pixel, x: 19, y: sweatY, width: 2, height: 3, color: color)
            drawRect(in: context, origin: origin, pixel: pixel, x: 20, y: sweatY + 3, width: 1, height: 1, color: color)
        case .awaitJump, .shieldWait:
            let flash = frame % 4 < 2
            drawRect(in: context, origin: origin, pixel: pixel, x: 19, y: 3, width: 1, height: 4, color: flash ? palette.warning : palette.spark)
            drawRect(in: context, origin: origin, pixel: pixel, x: 19, y: 8, width: 1, height: 1, color: flash ? palette.warning : palette.spark)
            if animation == .shieldWait {
                drawRect(in: context, origin: origin, pixel: pixel, x: 3, y: 9, width: 2, height: 8, color: palette.accent.opacity(0.72))
                drawRect(in: context, origin: origin, pixel: pixel, x: 19, y: 9, width: 2, height: 8, color: palette.accent.opacity(0.72))
            }
        case .eatToken, .tokenOrbit:
            let tokenX = max(14, 22 - frame)
            drawRect(in: context, origin: origin, pixel: pixel, x: tokenX, y: 11, width: 4, height: 4, color: palette.outline)
            drawRect(in: context, origin: origin, pixel: pixel, x: tokenX + 1, y: 12, width: 2, height: 2, color: palette.token)
            drawRect(in: context, origin: origin, pixel: pixel, x: tokenX + 2, y: 11, width: 1, height: 4, color: palette.spark)
            if animation == .tokenOrbit {
                drawRect(in: context, origin: origin, pixel: pixel, x: 4 + frame % 5, y: 5, width: 2, height: 2, color: palette.token)
            }
        case .evolveGlow, .celebrateDance, .maxVictory:
            let glow = frame % 2 == 0
            let sparkleColor = glow ? palette.spark : palette.accent
            drawRect(in: context, origin: origin, pixel: pixel, x: 4, y: 5, width: 2, height: 2, color: sparkleColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: 19, y: 4, width: 2, height: 2, color: sparkleColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: 3, y: 18, width: 2, height: 2, color: sparkleColor)
            drawRect(in: context, origin: origin, pixel: pixel, x: 21, y: 17, width: 1, height: 3, color: sparkleColor)
        case .happyBounce:
            drawRect(in: context, origin: origin, pixel: pixel, x: 6, y: 6, width: 2, height: 2, color: palette.spark)
            drawRect(in: context, origin: origin, pixel: pixel, x: 18, y: 7, width: 2, height: 2, color: palette.spark)
        case .nap:
            drawRect(in: context, origin: origin, pixel: pixel, x: 18, y: 4, width: 2, height: 1, color: palette.screenGlyph)
            drawRect(in: context, origin: origin, pixel: pixel, x: 19, y: 3, width: 2, height: 1, color: palette.screenGlyph)
        default:
            break
        }
    }

    private func drawPrestigeSparkles(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let sparkleCount = min(level / 25, 3)
        guard sparkleCount > 0 else {
            return
        }

        let points = [
            (x: 3, y: 6 + frame % 2),
            (x: 20, y: 7 + (frame + 1) % 2),
            (x: 5, y: 18 - frame % 2)
        ]

        for index in 0..<sparkleCount {
            let point = points[index]
            drawRect(in: context, origin: origin, pixel: pixel, x: point.x, y: point.y, width: 2, height: 1, color: palette.spark)
            drawRect(in: context, origin: origin, pixel: pixel, x: point.x + 1, y: point.y - 1, width: 1, height: 3, color: palette.spark.opacity(0.86))
        }
    }

    private func drawFallenPet(in context: GraphicsContext, origin: CGPoint, pixel: CGFloat) {
        let slide = min(frame, 6) / 2

        drawRect(in: context, origin: origin, pixel: pixel, x: 5 + slide, y: 14, width: 14, height: 6, color: palette.outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 6 + slide, y: 15, width: 12, height: 4, color: palette.mutedBody)
        drawRect(in: context, origin: origin, pixel: pixel, x: 8 + slide, y: 15, width: 8, height: 3, color: palette.screenOutline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 9 + slide, y: 16, width: 6, height: 1, color: palette.mutedScreen)

        drawRect(in: context, origin: origin, pixel: pixel, x: 10 + slide, y: 16, width: 1, height: 1, color: palette.warning)
        drawRect(in: context, origin: origin, pixel: pixel, x: 12 + slide, y: 16, width: 1, height: 1, color: palette.warning)
        drawRect(in: context, origin: origin, pixel: pixel, x: 11 + slide, y: 17, width: 1, height: 1, color: palette.warning)
        drawRect(in: context, origin: origin, pixel: pixel, x: 14 + slide, y: 16, width: 2, height: 1, color: palette.warning)

        drawRect(in: context, origin: origin, pixel: pixel, x: 4 + slide, y: 18, width: 4, height: 2, color: palette.outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 16 + slide, y: 18, width: 4, height: 2, color: palette.outline)
        drawRect(in: context, origin: origin, pixel: pixel, x: 7, y: 7, width: 2, height: 2, color: palette.token)
        drawRect(in: context, origin: origin, pixel: pixel, x: 20, y: 8, width: 2, height: 2, color: palette.token)
    }

    private func drawRuns(
        _ runs: [PixelRun],
        in context: GraphicsContext,
        origin: CGPoint,
        pixel: CGFloat,
        color: Color
    ) {
        for run in runs where run.width > 0 {
            drawRect(in: context, origin: origin, pixel: pixel, x: run.x, y: run.y, width: run.width, height: 1, color: color)
        }
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
        case .idleBreathe, .spiritIdle:
            return CGPoint(x: 0, y: frame % 4 < 2 ? -1 : 0)
        case .hoverIdle:
            return CGPoint(x: 0, y: frame % 4 < 2 ? -2 : -1)
        case .idleStretch:
            return CGPoint(x: 0, y: frame % 6 < 3 ? -1 : 0)
        case .thinkSweat, .bubbleThink:
            return CGPoint(x: frame % 4 == 0 ? -1 : 0, y: 0)
        case .talkWalk, .outputBurst:
            return CGPoint(x: frame % 4 < 2 ? -1 : 1, y: frame % 2 == 0 ? -1 : 0)
        case .awaitJump, .shieldWait:
            return CGPoint(x: 0, y: frame < 5 ? -3 : -1)
        case .eatToken, .evolveGlow, .tokenOrbit, .celebrateDance, .maxVictory, .happyBounce:
            return CGPoint(x: frame % 2 == 0 ? 0 : 1, y: frame % 4 == 0 ? -1 : 0)
        case .nap:
            return CGPoint(x: 0, y: 1)
        case .errorFall:
            return .zero
        }
    }

    private var pupilShift: Int {
        switch animation {
        case .thinkSweat, .bubbleThink:
            return frame % 4 == 0 ? -1 : 0
        case .talkWalk, .outputBurst, .eatToken, .tokenOrbit, .evolveGlow, .celebrateDance, .maxVictory:
            return 1
        default:
            return 0
        }
    }

    private var palette: PixelPetPalette {
        form.codexPetPalette
    }

    private var bodyColor: Color {
        switch animation {
        case .evolveGlow, .celebrateDance, .maxVictory:
            return palette.glowBody
        case .thinkSweat, .bubbleThink:
            return palette.focusBody
        case .awaitJump, .shieldWait:
            return palette.alertBody
        default:
            return palette.body
        }
    }

    private var bodyShadowColor: Color {
        switch animation {
        case .evolveGlow, .celebrateDance, .maxVictory:
            return palette.glowShadow
        case .thinkSweat, .bubbleThink:
            return palette.focusShadow
        case .awaitJump, .shieldWait:
            return palette.alertShadow
        default:
            return palette.bodyShadow
        }
    }

    private var bellyColor: Color {
        animation == .awaitJump || animation == .shieldWait ? palette.alertBelly : palette.belly
    }

    private var screenColor: Color {
        animation == .awaitJump || animation == .shieldWait ? palette.alertScreen : palette.screen
    }

    private var faceGlyphColor: Color {
        animation == .awaitJump || animation == .shieldWait ? palette.warning : palette.screenGlyph
    }
}

private struct PixelRun {
    let x: Int
    let y: Int
    let width: Int
}

private struct PixelPetPalette {
    let outline: Color
    let screenOutline: Color
    let screen: Color
    let screenGlyph: Color
    let screenGlint: Color
    let body: Color
    let bodyShadow: Color
    let belly: Color
    let highlight: Color
    let rimLight: Color
    let accent: Color
    let leaf: Color
    let fin: Color
    let shell: Color
    let shield: Color
    let crystal: Color
    let star: Color
    let foot: Color
    let token: Color
    let spark: Color
    let sweat: Color
    let warning: Color
    let mouth: Color
    let focusBody: Color
    let focusShadow: Color
    let alertBody: Color
    let alertShadow: Color
    let alertBelly: Color
    let alertScreen: Color
    let glowBody: Color
    let glowShadow: Color
    let mutedBody: Color
    let mutedScreen: Color
}

private extension PetForm {
    var codexPetPalette: PixelPetPalette {
        let lightBlue = Color(red: 0.46, green: 0.66, blue: 1.0)

        let body: Color
        let shadow: Color
        let belly: Color
        let accent: Color
        let leaf: Color
        let fin: Color
        let screen: Color
        let glyph: Color
        let foot: Color

        switch self {
        case .core:
            body = Color(red: 0.28, green: 0.49, blue: 0.98)
            shadow = Color(red: 0.16, green: 0.30, blue: 0.78)
            belly = Color(red: 0.40, green: 0.58, blue: 0.96)
            accent = Color(red: 0.47, green: 0.92, blue: 1.0)
            leaf = Color(red: 0.63, green: 0.95, blue: 0.56)
            fin = Color(red: 0.23, green: 0.43, blue: 0.90)
            screen = Color(red: 0.05, green: 0.16, blue: 0.30)
            glyph = Color(red: 0.58, green: 0.97, blue: 1.0)
            foot = Color(red: 0.10, green: 0.27, blue: 0.76)
        case .antenna:
            body = Color(red: 0.30, green: 0.52, blue: 1.0)
            shadow = Color(red: 0.16, green: 0.31, blue: 0.78)
            belly = Color(red: 0.43, green: 0.61, blue: 0.98)
            accent = Color(red: 0.62, green: 0.92, blue: 0.38)
            leaf = Color(red: 0.58, green: 0.94, blue: 0.38)
            fin = Color(red: 0.23, green: 0.45, blue: 0.92)
            screen = Color(red: 0.05, green: 0.16, blue: 0.30)
            glyph = Color(red: 0.58, green: 0.97, blue: 1.0)
            foot = Color(red: 0.10, green: 0.28, blue: 0.78)
        case .ripple:
            body = Color(red: 0.26, green: 0.60, blue: 1.0)
            shadow = Color(red: 0.12, green: 0.36, blue: 0.82)
            belly = Color(red: 0.48, green: 0.72, blue: 1.0)
            accent = Color(red: 0.84, green: 0.98, blue: 1.0)
            leaf = Color(red: 0.58, green: 0.94, blue: 0.38)
            fin = Color(red: 0.20, green: 0.52, blue: 0.94)
            screen = Color(red: 0.04, green: 0.18, blue: 0.33)
            glyph = Color(red: 0.64, green: 0.98, blue: 1.0)
            foot = Color(red: 0.08, green: 0.34, blue: 0.82)
        case .shell:
            body = Color(red: 0.30, green: 0.52, blue: 0.96)
            shadow = Color(red: 0.18, green: 0.30, blue: 0.72)
            belly = Color(red: 0.55, green: 0.68, blue: 1.0)
            accent = Color(red: 0.70, green: 0.78, blue: 0.94)
            leaf = Color(red: 0.58, green: 0.94, blue: 0.38)
            fin = Color(red: 0.42, green: 0.45, blue: 0.62)
            screen = Color(red: 0.06, green: 0.15, blue: 0.28)
            glyph = Color(red: 0.78, green: 1.0, blue: 1.0)
            foot = Color(red: 0.16, green: 0.28, blue: 0.70)
        case .spark:
            body = Color(red: 0.33, green: 0.52, blue: 1.0)
            shadow = Color(red: 0.18, green: 0.30, blue: 0.78)
            belly = Color(red: 0.58, green: 0.68, blue: 1.0)
            accent = Color(red: 1.0, green: 0.76, blue: 0.28)
            leaf = Color(red: 0.78, green: 0.96, blue: 0.42)
            fin = Color(red: 0.28, green: 0.45, blue: 0.92)
            screen = Color(red: 0.06, green: 0.16, blue: 0.30)
            glyph = Color(red: 0.64, green: 0.98, blue: 1.0)
            foot = Color(red: 0.12, green: 0.30, blue: 0.78)
        case .glider:
            body = Color(red: 0.35, green: 0.60, blue: 1.0)
            shadow = Color(red: 0.15, green: 0.36, blue: 0.84)
            belly = Color(red: 0.50, green: 0.76, blue: 1.0)
            accent = Color(red: 0.50, green: 0.98, blue: 1.0)
            leaf = Color(red: 0.68, green: 0.98, blue: 0.55)
            fin = Color(red: 0.23, green: 0.70, blue: 1.0)
            screen = Color(red: 0.06, green: 0.17, blue: 0.34)
            glyph = Color(red: 0.78, green: 1.0, blue: 1.0)
            foot = Color(red: 0.12, green: 0.35, blue: 0.82)
        case .shield:
            body = Color(red: 0.36, green: 0.54, blue: 1.0)
            shadow = Color(red: 0.18, green: 0.32, blue: 0.82)
            belly = Color(red: 0.58, green: 0.72, blue: 1.0)
            accent = Color(red: 1.0, green: 0.76, blue: 0.28)
            leaf = Color(red: 0.70, green: 0.96, blue: 0.52)
            fin = Color(red: 0.36, green: 0.52, blue: 0.98)
            screen = Color(red: 0.06, green: 0.16, blue: 0.34)
            glyph = Color(red: 0.80, green: 1.0, blue: 1.0)
            foot = Color(red: 0.14, green: 0.34, blue: 0.82)
        case .crystal:
            body = Color(red: 0.36, green: 0.64, blue: 1.0)
            shadow = Color(red: 0.16, green: 0.40, blue: 0.84)
            belly = Color(red: 0.54, green: 0.84, blue: 1.0)
            accent = Color(red: 0.72, green: 0.94, blue: 1.0)
            leaf = Color(red: 0.56, green: 0.92, blue: 1.0)
            fin = Color(red: 0.52, green: 0.45, blue: 1.0)
            screen = Color(red: 0.07, green: 0.16, blue: 0.36)
            glyph = Color(red: 0.90, green: 1.0, blue: 1.0)
            foot = Color(red: 0.16, green: 0.36, blue: 0.84)
        case .star:
            body = Color(red: 0.42, green: 0.52, blue: 1.0)
            shadow = Color(red: 0.22, green: 0.28, blue: 0.78)
            belly = Color(red: 0.60, green: 0.66, blue: 1.0)
            accent = Color(red: 1.0, green: 0.84, blue: 0.30)
            leaf = Color(red: 0.78, green: 0.98, blue: 0.78)
            fin = Color(red: 0.58, green: 0.50, blue: 1.0)
            screen = Color(red: 0.08, green: 0.12, blue: 0.32)
            glyph = Color(red: 0.78, green: 1.0, blue: 1.0)
            foot = Color(red: 0.18, green: 0.24, blue: 0.72)
        case .spirit:
            body = Color(red: 0.54, green: 0.58, blue: 1.0)
            shadow = Color(red: 0.28, green: 0.30, blue: 0.78)
            belly = Color(red: 0.70, green: 0.76, blue: 1.0)
            accent = Color(red: 0.92, green: 0.72, blue: 1.0)
            leaf = Color(red: 0.72, green: 0.98, blue: 0.72)
            fin = Color(red: 0.55, green: 0.52, blue: 1.0)
            screen = Color(red: 0.04, green: 0.13, blue: 0.28)
            glyph = Color(red: 0.74, green: 1.0, blue: 1.0)
            foot = Color(red: 0.20, green: 0.20, blue: 0.68)
        }

        return PixelPetPalette(
            outline: Color(red: 0.03, green: 0.05, blue: 0.10),
            screenOutline: Color(red: 0.07, green: 0.12, blue: 0.26),
            screen: screen,
            screenGlyph: glyph,
            screenGlint: lightBlue,
            body: body,
            bodyShadow: shadow,
            belly: belly,
            highlight: Color.white.opacity(0.52),
            rimLight: lightBlue,
            accent: accent,
            leaf: leaf,
            fin: fin,
            shell: Color(red: 0.55, green: 0.66, blue: 0.92),
            shield: Color(red: 0.64, green: 0.88, blue: 1.0),
            crystal: Color(red: 0.66, green: 0.96, blue: 1.0),
            star: Color(red: 1.0, green: 0.86, blue: 0.34),
            foot: foot,
            token: Color(red: 1.0, green: 0.75, blue: 0.20),
            spark: Color(red: 1.0, green: 0.94, blue: 0.54),
            sweat: Color(red: 0.46, green: 0.86, blue: 1.0),
            warning: Color(red: 1.0, green: 0.33, blue: 0.43),
            mouth: Color(red: 1.0, green: 0.55, blue: 0.66),
            focusBody: Color(red: 0.92, green: 0.72, blue: 0.30),
            focusShadow: Color(red: 0.70, green: 0.49, blue: 0.18),
            alertBody: Color(red: 0.96, green: 0.36, blue: 0.58),
            alertShadow: Color(red: 0.69, green: 0.17, blue: 0.38),
            alertBelly: Color(red: 1.0, green: 0.58, blue: 0.74),
            alertScreen: Color(red: 0.22, green: 0.08, blue: 0.16),
            glowBody: Color(red: 0.98, green: 0.74, blue: 0.24),
            glowShadow: Color(red: 0.78, green: 0.44, blue: 0.10),
            mutedBody: Color(red: 0.36, green: 0.43, blue: 0.55),
            mutedScreen: Color(red: 0.12, green: 0.17, blue: 0.23)
        )
    }
}
