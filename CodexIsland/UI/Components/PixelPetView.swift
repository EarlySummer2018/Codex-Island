import AppKit
import Foundation
import ImageIO
import SwiftUI

struct PixelPetView: View {
    let animationName: PetAnimation
    var size: CGFloat = 24
    var form: PetForm = .original
    var level: Int = 0
    var feedTrigger: UUID?
    var isFacingLeft: Bool?

    @State private var currentFrame = 0
    @State private var activeAnimation: PetAnimation = .idleBreathe
    @State private var animationTimer: Timer?
    @State private var idleStretchWorkItem: DispatchWorkItem?

    var body: some View {
        furinaFrameView(animation: activeAnimation, frame: currentFrame)
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
        .onDisappear {
            stopAnimation()
        }
        .accessibilityLabel("Furina Codex pet")
    }

    @ViewBuilder
    private func furinaFrameView(animation: PetAnimation, frame: Int) -> some View {
        let atlasState = animation.furinaAtlasState(facingLeft: isFacingLeft)

        if let image = FurinaPetAtlas.shared.image(for: atlasState, frame: frame, form: form) {
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

        let frameCount = max(animation.furinaFrameCount(facingLeft: isFacingLeft), 1)
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

struct FurinaPetFrameKey: Hashable {
    let state: FurinaPetAtlasState
    let column: Int
    let form: PetForm
}

final class FurinaPetAtlas {
    static let shared = FurinaPetAtlas()

    private var spriteSheet: CGImage?
    private var frameCache: [FurinaPetFrameKey: NSImage] = [:]
    private let frameCacheLimit = 180

    private init() {}

    func image(for state: FurinaPetAtlasState, frame: Int, form: PetForm) -> NSImage? {
        let column = FurinaPetAtlasSpec.normalizedFrameIndex(frame, for: state)
        let key = FurinaPetFrameKey(state: state, column: column, form: form)

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

        let frameImage = FurinaPetRecoloring.recoloredImage(croppedFrame, form: form)
        let image = NSImage(
            cgImage: frameImage,
            size: NSSize(
                width: FurinaPetAtlasSpec.cellWidth,
                height: FurinaPetAtlasSpec.cellHeight
            )
        )

        if frameCache.count >= frameCacheLimit {
            frameCache.removeAll(keepingCapacity: true)
        }
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

enum FurinaRecolorPart: Hashable {
    case shoes
    case legs
    case cape
    case skirt
    case sleeves
    case top
    case ornament
    case hat
    case hairTips
}

extension PetForm {
    var furinaRecolorParts: Set<FurinaRecolorPart> {
        switch self {
        case .original:
            return []
        case .shoesPink:
            return [.shoes]
        case .legsPink:
            return [.shoes, .legs]
        case .capePink:
            return [.shoes, .legs, .cape]
        case .skirtPink:
            return [.shoes, .legs, .cape, .skirt]
        case .sleevesPink:
            return [.shoes, .legs, .cape, .skirt, .sleeves]
        case .topPink:
            return [.shoes, .legs, .cape, .skirt, .sleeves, .top]
        case .ornamentRose:
            return [.shoes, .legs, .cape, .skirt, .sleeves, .top, .ornament]
        case .hatPink:
            return [.shoes, .legs, .cape, .skirt, .sleeves, .top, .ornament, .hat]
        case .hairPink:
            return [.shoes, .legs, .cape, .skirt, .sleeves, .top, .ornament, .hat, .hairTips]
        case .fullPink:
            return [.shoes, .legs, .cape, .skirt, .sleeves, .top, .ornament, .hat, .hairTips]
        }
    }
}

enum FurinaPetRecoloring {
    static func recoloredImage(_ source: CGImage, form: PetForm) -> CGImage {
        guard form != .original else {
            return source
        }

        let width = source.width
        let height = source.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return source
        }

        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return source
        }

        let parts = form.furinaRecolorParts
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let alpha = data[offset + 3]
                guard alpha > 0 else {
                    continue
                }

                let pixel = FurinaSourcePixel(
                    red: data[offset],
                    green: data[offset + 1],
                    blue: data[offset + 2],
                    alpha: alpha,
                    x: CGFloat(x) / CGFloat(max(width - 1, 1)),
                    y: CGFloat(y) / CGFloat(max(height - 1, 1))
                )

                guard let target = recolorTarget(for: pixel, form: form, parts: parts) else {
                    continue
                }

                let color = recolored(pixel, target: target)
                let alphaScale = Double(alpha) / 255
                data[offset] = UInt8(clamping: Int((color.red * alphaScale).rounded()))
                data[offset + 1] = UInt8(clamping: Int((color.green * alphaScale).rounded()))
                data[offset + 2] = UInt8(clamping: Int((color.blue * alphaScale).rounded()))
            }
        }

        return context.makeImage() ?? source
    }

    private static func recolorTarget(
        for pixel: FurinaSourcePixel,
        form: PetForm,
        parts: Set<FurinaRecolorPart>
    ) -> FurinaTargetColor? {
        if form == .fullPink {
            if pixel.isHairHighlight && region(.hairTips, contains: pixel) {
                return .hairPink
            }

            if pixel.isGoldOrnament {
                return .ornamentRose
            }

            if pixel.isBlueOutfit {
                return .outfitPink
            }

            return nil
        }

        for part in parts where region(part, contains: pixel) {
            switch part {
            case .ornament:
                if pixel.isGoldOrnament {
                    return .ornamentRose
                }
            case .hairTips:
                if pixel.isHairHighlight {
                    return .hairPink
                }
            case .hat:
                if pixel.isBlueOutfit || pixel.isGoldOrnament {
                    return pixel.isGoldOrnament ? .ornamentRose : .outfitPink
                }
            case .shoes, .legs, .cape, .skirt, .sleeves, .top:
                if pixel.isBlueOutfit {
                    return .outfitPink
                }
            }
        }

        return nil
    }

    private static func region(_ part: FurinaRecolorPart, contains pixel: FurinaSourcePixel) -> Bool {
        let x = pixel.x
        let y = pixel.y

        switch part {
        case .shoes:
            return (0.30...0.70).contains(x) && (0.76...0.94).contains(y)
        case .legs:
            return (0.34...0.66).contains(x) && (0.63...0.82).contains(y)
        case .cape:
            return (0.18...0.40).contains(x) && (0.30...0.78).contains(y)
                || (0.60...0.84).contains(x) && (0.30...0.78).contains(y)
        case .skirt:
            return (0.30...0.70).contains(x) && (0.50...0.70).contains(y)
        case .sleeves:
            return (0.20...0.43).contains(x) && (0.34...0.62).contains(y)
                || (0.57...0.80).contains(x) && (0.34...0.62).contains(y)
        case .top:
            return (0.34...0.66).contains(x) && (0.34...0.56).contains(y)
        case .ornament:
            return (0.24...0.78).contains(x) && (0.06...0.70).contains(y)
        case .hat:
            return (0.32...0.76).contains(x) && (0.04...0.30).contains(y)
        case .hairTips:
            return ((0.12...0.44).contains(x) || (0.56...0.90).contains(x))
                && (0.22...0.66).contains(y)
        }
    }

    private static func recolored(
        _ pixel: FurinaSourcePixel,
        target: FurinaTargetColor
    ) -> (red: Double, green: Double, blue: Double) {
        let brightness = max(pixel.red, pixel.green, pixel.blue) / 255
        let luminance = (pixel.red * 0.2126 + pixel.green * 0.7152 + pixel.blue * 0.0722) / 255
        let detail = min(max(brightness * 0.62 + luminance * 0.58, 0.18), 1.18)
        let base = target.rgb
        let highlight = max(brightness - 0.72, 0) * 0.55

        return (
            red: min(base.red * detail + 255 * highlight, 255),
            green: min(base.green * detail + 230 * highlight, 255),
            blue: min(base.blue * detail + 245 * highlight, 255)
        )
    }
}

struct FurinaSourcePixel {
    let redByte: UInt8
    let greenByte: UInt8
    let blueByte: UInt8
    let alpha: UInt8
    let x: CGFloat
    let y: CGFloat

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8, x: CGFloat, y: CGFloat) {
        self.redByte = red
        self.greenByte = green
        self.blueByte = blue
        self.alpha = alpha
        self.x = x
        self.y = y
    }

    var red: Double {
        unpremultiplied(redByte)
    }

    var green: Double {
        unpremultiplied(greenByte)
    }

    var blue: Double {
        unpremultiplied(blueByte)
    }

    var isBlueOutfit: Bool {
        guard alpha > 24 else {
            return false
        }

        let maxChannel = max(red, green, blue)
        let minChannel = min(red, green, blue)
        let saturation = maxChannel <= 0 ? 0 : (maxChannel - minChannel) / maxChannel
        let brightBlue = blue > 58 && blue > red * 1.14 && blue > green * 0.82 && saturation > 0.16
        let deepNavy = blue > 34 && blue > red + 10 && blue > green + 4 && saturation > 0.12

        return brightBlue || deepNavy
    }

    var isGoldOrnament: Bool {
        guard alpha > 32 else {
            return false
        }

        return red > 118 && green > 72 && blue < 112 && red > blue * 1.42 && green > blue * 0.95
    }

    var isHairHighlight: Bool {
        guard alpha > 36 else {
            return false
        }

        let maxChannel = max(red, green, blue)
        let minChannel = min(red, green, blue)
        return maxChannel > 150
            && minChannel > 105
            && blue >= red * 0.86
            && green >= red * 0.76
    }

    private func unpremultiplied(_ value: UInt8) -> Double {
        let alphaScale = Double(alpha) / 255
        guard alphaScale > 0 else {
            return 0
        }

        return min(Double(value) / alphaScale, 255)
    }
}

enum FurinaTargetColor {
    case outfitPink
    case ornamentRose
    case hairPink

    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .outfitPink:
            return (245, 34, 132)
        case .ornamentRose:
            return (255, 88, 164)
        case .hairPink:
            return (255, 118, 196)
        }
    }
}
