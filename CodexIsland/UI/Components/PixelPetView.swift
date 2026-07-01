import AppKit
import Foundation
import ImageIO
import SwiftUI

struct PixelPetView: View {
    let animationName: PetAnimation
    var size: CGFloat = 24
    var form: PetForm = .core
    var level: Int = 0
    var feedTrigger: UUID?
    var levelUpTrigger: UUID?
    var statusEffect: PetStatusEffect = .none
    var showsGroundShadow = true
    var isFacingLeft: Bool?

    @State private var currentFrame = 0
    @State private var activeAnimation: PetAnimation = .idleBreathe
    @State private var animationTimer: Timer?
    @State private var idleStretchWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack {
            furinaFrameView(animation: activeAnimation, frame: currentFrame)

            PetStatusEffectOverlay(
                effect: effectiveStatusEffect,
                frame: currentFrame,
                size: size
            )

            if activeAnimation == .awaitJump || effectiveStatusEffect == .awaitingInput {
                PulseRingView(size: max(size * 0.58, 12))
                    .offset(y: -size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            startBaseAnimation(animationName)
        }
        .onChange(of: animationName) { newAnimation in
            startBaseAnimation(newAnimation)
        }
        .onChange(of: feedTrigger) { trigger in
            guard trigger != nil else {
                return
            }

            startOneShotAnimation(PetAnimation.feedAnimation(for: level))
        }
        .onChange(of: levelUpTrigger) { trigger in
            guard trigger != nil else {
                return
            }

            startOneShotAnimation(PetAnimation.levelUpAnimation(for: level))
        }
        .onDisappear {
            stopAnimation()
        }
        .accessibilityLabel("Furina Codex pet")
    }

    @ViewBuilder
    private func furinaFrameView(animation: PetAnimation, frame: Int) -> some View {
        let atlasState = animation.furinaAtlasState(facingLeft: isFacingLeft)

        if let image = FurinaPetAtlas.shared.image(for: atlasState, frame: frame) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Color.clear
                .frame(width: size, height: size)
        }
    }

    private var effectiveStatusEffect: PetStatusEffect {
        statusEffect == .none ? activeAnimation.inferredStatusEffect : statusEffect
    }

    private func startBaseAnimation(_ animation: PetAnimation) {
        startAnimation(animation)
    }

    private func startOneShotAnimation(_ animation: PetAnimation) {
        startAnimation(animation) {
            startBaseAnimation(animationName)
        }
    }

    private func startAnimation(_ animation: PetAnimation, completion: (() -> Void)? = nil) {
        stopAnimation()

        activeAnimation = animation
        currentFrame = 0

        let frameCount = max(animation.frameCount, 1)
        var advancedFrames = 0

        let timer = Timer(timeInterval: 1.0 / Double(animation.fps), repeats: true) { timer in
            advancedFrames += 1

            if let loops = animation.loops, advancedFrames >= frameCount * loops {
                currentFrame = frameCount - 1
                timer.invalidate()
                animationTimer = nil
                completion?()
                return
            }

            currentFrame = advancedFrames % frameCount
        }

        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        if animation.isIdleLoop {
            scheduleIdleStretch()
        }
    }

    private func scheduleIdleStretch() {
        let delay = Double.random(in: 30...90)
        let workItem = DispatchWorkItem {
            guard animationName.isIdleLoop,
                  activeAnimation.isIdleLoop else {
                return
            }

            startAnimation(PetAnimation.idleBreakAnimation(for: level)) {
                startBaseAnimation(animationName)
            }
        }

        idleStretchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil

        idleStretchWorkItem?.cancel()
        idleStretchWorkItem = nil
    }
}

private struct FurinaPetFrameKey: Hashable {
    let state: FurinaPetAtlasState
    let column: Int
}

private final class FurinaPetAtlas {
    static let shared = FurinaPetAtlas()

    private var spriteSheet: CGImage?
    private var frameCache: [FurinaPetFrameKey: NSImage] = [:]

    private init() {}

    func image(for state: FurinaPetAtlasState, frame: Int) -> NSImage? {
        let column = FurinaPetAtlasSpec.normalizedFrameIndex(frame)
        let key = FurinaPetFrameKey(state: state, column: column)

        if let cached = frameCache[key] {
            return cached
        }

        guard let sheet = spriteSheetImage(),
              sheet.width >= FurinaPetAtlasSpec.atlasWidth,
              sheet.height >= FurinaPetAtlasSpec.atlasHeight else {
            return nil
        }

        let cropRect = CGRect(
            x: column * FurinaPetAtlasSpec.cellWidth,
            y: state.row * FurinaPetAtlasSpec.cellHeight,
            width: FurinaPetAtlasSpec.cellWidth,
            height: FurinaPetAtlasSpec.cellHeight
        )

        guard let croppedFrame = sheet.cropping(to: cropRect) else {
            return nil
        }

        let image = NSImage(
            cgImage: croppedFrame,
            size: NSSize(
                width: FurinaPetAtlasSpec.cellWidth,
                height: FurinaPetAtlasSpec.cellHeight
            )
        )
        frameCache[key] = image
        return image
    }

    private func spriteSheetImage() -> CGImage? {
        if let spriteSheet {
            return spriteSheet
        }

        guard let dataAsset = NSDataAsset(name: FurinaPetAtlasSpec.assetName),
              let imageSource = CGImageSourceCreateWithData(dataAsset.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        spriteSheet = image
        return image
    }
}

private struct PetStatusEffectOverlay: View {
    let effect: PetStatusEffect
    let frame: Int
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            draw(effect: effect, frame: frame, in: context, canvasSize: canvasSize)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    private func draw(
        effect: PetStatusEffect,
        frame: Int,
        in context: GraphicsContext,
        canvasSize: CGSize
    ) {
        guard effect != .none else {
            return
        }

        let pixel = max(min(canvasSize.width, canvasSize.height) / 24, 1)
        switch effect {
        case .none:
            break
        case .thinking:
            drawThinking(in: context, canvasSize: canvasSize, pixel: pixel)
        case .working:
            drawWorking(in: context, canvasSize: canvasSize, pixel: pixel)
        case .streaming:
            drawStreaming(in: context, canvasSize: canvasSize, pixel: pixel)
        case .awaitingInput:
            drawAwaiting(in: context, canvasSize: canvasSize, pixel: pixel)
        case .error:
            drawError(in: context, canvasSize: canvasSize, pixel: pixel)
        case .dragging:
            drawDragging(in: context, canvasSize: canvasSize, pixel: pixel)
        case .levelUp:
            drawLevelUp(in: context, canvasSize: canvasSize, pixel: pixel)
        }
    }

    private func drawThinking(in context: GraphicsContext, canvasSize: CGSize, pixel: CGFloat) {
        let y = canvasSize.height * 0.12
        let x = canvasSize.width * 0.58
        for index in 0..<3 {
            let lift = (frame + index) % 6 < 3 ? pixel : 0
            drawRect(
                in: context,
                x: x + CGFloat(index) * pixel * 3,
                y: y - lift,
                width: pixel * 1.6,
                height: pixel * 1.6,
                color: Color(red: 0.45, green: 0.76, blue: 1.0).opacity(index == frame % 3 ? 0.95 : 0.55)
            )
        }
    }

    private func drawWorking(in context: GraphicsContext, canvasSize: CGSize, pixel: CGFloat) {
        let y = canvasSize.height * 0.18
        let x = canvasSize.width * 0.18
        for index in 0..<4 {
            let active = (frame + index) % 4 == 0
            drawRect(
                in: context,
                x: x + CGFloat(index) * pixel * 2.5,
                y: y + (active ? -pixel : 0),
                width: pixel * 1.5,
                height: pixel * 1.5,
                color: Color(red: 0.55, green: 0.95, blue: 0.82).opacity(active ? 0.95 : 0.42)
            )
        }
    }

    private func drawStreaming(in context: GraphicsContext, canvasSize: CGSize, pixel: CGFloat) {
        for index in 0..<4 {
            let phase = CGFloat((frame + index * 2) % 8)
            drawRect(
                in: context,
                x: canvasSize.width * 0.12 + phase * pixel * 0.7,
                y: canvasSize.height * 0.70 - CGFloat(index % 2) * pixel * 2.2,
                width: pixel * 2.2,
                height: pixel * 1.2,
                color: Color(red: 0.17, green: 0.86, blue: 1.0).opacity(0.9 - Double(index) * 0.12)
            )
        }
    }

    private func drawAwaiting(in context: GraphicsContext, canvasSize: CGSize, pixel: CGFloat) {
        let x = canvasSize.width * 0.50
        let y = canvasSize.height * 0.10
        let color = Color(red: 1.0, green: 0.28, blue: 0.32).opacity(frame % 4 < 2 ? 0.98 : 0.55)
        drawRect(in: context, x: x, y: y, width: pixel * 1.8, height: pixel * 5.2, color: color)
        drawRect(in: context, x: x, y: y + pixel * 6.4, width: pixel * 1.8, height: pixel * 1.8, color: color)
    }

    private func drawError(in context: GraphicsContext, canvasSize: CGSize, pixel: CGFloat) {
        let color = Color(red: 1.0, green: 0.18, blue: 0.20).opacity(frame % 3 == 0 ? 0.96 : 0.62)
        drawRect(in: context, x: canvasSize.width * 0.20, y: canvasSize.height * 0.24, width: pixel * 5, height: pixel * 1.4, color: color)
        drawRect(in: context, x: canvasSize.width * 0.62, y: canvasSize.height * 0.60, width: pixel * 4, height: pixel * 1.4, color: color)
    }

    private func drawDragging(in context: GraphicsContext, canvasSize: CGSize, pixel: CGFloat) {
        let color = Color(red: 0.44, green: 0.78, blue: 1.0).opacity(0.82)
        drawRect(in: context, x: canvasSize.width * 0.28, y: canvasSize.height * 0.12, width: pixel * 3, height: pixel, color: color)
        drawRect(in: context, x: canvasSize.width * 0.60, y: canvasSize.height * 0.12, width: pixel * 3, height: pixel, color: color)
        drawRect(in: context, x: canvasSize.width * 0.36, y: canvasSize.height * 0.17, width: pixel * 7, height: pixel, color: color.opacity(0.68))
    }

    private func drawLevelUp(in context: GraphicsContext, canvasSize: CGSize, pixel: CGFloat) {
        let color = Color(red: 1.0, green: 0.82, blue: 0.24).opacity(frame % 4 < 2 ? 0.96 : 0.56)
        let centerX = canvasSize.width * 0.5
        let centerY = canvasSize.height * 0.44
        let radius = canvasSize.width * 0.35
        for index in 0..<8 {
            let angle = CGFloat(index) * (.pi / 4) + CGFloat(frame % 8) * 0.08
            drawRect(
                in: context,
                x: centerX + cos(angle) * radius,
                y: centerY + sin(angle) * radius,
                width: pixel * 1.6,
                height: pixel * 1.6,
                color: color
            )
        }
    }

    private func drawRect(
        in context: GraphicsContext,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        color: Color
    ) {
        context.fill(
            Path(CGRect(x: x, y: y, width: width, height: height)),
            with: .color(color)
        )
    }
}
