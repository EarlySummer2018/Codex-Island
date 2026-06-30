import AppKit
import Foundation
import SwiftUI

struct PixelPetView: View {
    let animationName: PetAnimation
    var size: CGFloat = 24
    var form: PetForm = .core
    var level: Int = 0
    var feedTrigger: UUID?
    var levelUpTrigger: UUID?

    @State private var currentFrame = 0
    @State private var activeAnimation: PetAnimation = .idleBreathe
    @State private var animationTimer: Timer?
    @State private var idleStretchWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack {
            petFrameView(animation: activeAnimation, frame: currentFrame)

            if activeAnimation == .awaitJump {
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
        .accessibilityLabel("Codex pixel pet")
    }

    @ViewBuilder
    private func petFrameView(animation: PetAnimation, frame: Int) -> some View {
        let frameIndex = frame % max(animation.frameCount, 1)
        let formImageName = "pet_\(form.assetName)_\(animation.rawValue)_\(String(format: "%02d", frameIndex))"
        let imageName = "pet_\(animation.rawValue)_\(String(format: "%02d", frameIndex))"

        if let image = NSImage(named: formImageName) ?? NSImage(named: imageName) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            PlaceholderPetView(
                animation: animation,
                frame: frameIndex,
                size: size,
                form: form,
                level: level
            )
        }
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
