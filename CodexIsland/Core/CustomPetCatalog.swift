import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CustomPetStage: Int, CaseIterable, Codable, Hashable {
    case stage1 = 1
    case stage2
    case stage3
    case stage4
    case stage5
    case stage6
    case stage7
    case stage8
    case stage9
    case stage10

    var directoryName: String {
        switch self {
        case .stage1: return "01-lv00-09"
        case .stage2: return "02-lv10-19"
        case .stage3: return "03-lv20-29"
        case .stage4: return "04-lv30-39"
        case .stage5: return "05-lv40-49"
        case .stage6: return "06-lv50-59"
        case .stage7: return "07-lv60-69"
        case .stage8: return "08-lv70-79"
        case .stage9: return "09-lv80-89"
        case .stage10: return "10-lv90-100"
        }
    }

    static func stage(for form: PetForm) -> CustomPetStage {
        switch form {
        case .original: return .stage1
        case .shoesPink: return .stage2
        case .legsPink: return .stage3
        case .capePink: return .stage4
        case .skirtPink: return .stage5
        case .sleevesPink: return .stage6
        case .topPink: return .stage7
        case .ornamentRose: return .stage8
        case .hatPink: return .stage9
        case .hairPink, .fullPink: return .stage10
        }
    }

    static func stage(forLevel level: Int) -> CustomPetStage {
        stage(for: PetForm.form(for: level))
    }
}

struct CodexPetManifest: Codable, Equatable {
    let id: String
    let displayName: String
    let description: String
    let spritesheetPath: String
}

struct CustomPetPackage: Equatable {
    let stage: CustomPetStage
    let directoryURL: URL
    let manifest: CodexPetManifest
    let spritesheetURL: URL
}

final class CustomPetCatalog {
    static let shared = CustomPetCatalog(
        rootDirectory: AppDirectories.customPetStagesDirectory()
    )

    let rootDirectory: URL
    private(set) var packages: [CustomPetStage: CustomPetPackage] = [:]

    private let fileManager: FileManager

    init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileManager = fileManager

        prepareDirectories()
        packages = scanPackages()
    }

    static func bootstrap() {
        _ = shared
    }

    func package(for form: PetForm) -> CustomPetPackage? {
        packages[CustomPetStage.stage(for: form)]
    }

    func directory(for stage: CustomPetStage) -> URL {
        rootDirectory.appendingPathComponent(stage.directoryName, isDirectory: true)
    }

    private func prepareDirectories() {
        try? fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )

        for stage in CustomPetStage.allCases {
            try? fileManager.createDirectory(
                at: directory(for: stage),
                withIntermediateDirectories: true
            )
        }
    }

    private func scanPackages() -> [CustomPetStage: CustomPetPackage] {
        var discovered: [CustomPetStage: CustomPetPackage] = [:]

        for stage in CustomPetStage.allCases {
            guard let package = loadPackage(for: stage) else {
                continue
            }
            discovered[stage] = package
        }

        return discovered
    }

    private func loadPackage(for stage: CustomPetStage) -> CustomPetPackage? {
        let stageDirectory = directory(for: stage)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: stageDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              isExpectedStageDirectory(stageDirectory, for: stage) else {
            return nil
        }

        let manifestURL = stageDirectory.appendingPathComponent("pet.json", isDirectory: false)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(CodexPetManifest.self, from: data),
              isValid(manifest: manifest) else {
            return nil
        }

        guard let spritesheetURL = safeSpritesheetURL(
            path: manifest.spritesheetPath,
            inside: stageDirectory
        ) else {
            return nil
        }

        var spritesheetIsDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: spritesheetURL.path,
            isDirectory: &spritesheetIsDirectory
        ), !spritesheetIsDirectory.boolValue else {
            return nil
        }

        return CustomPetPackage(
            stage: stage,
            directoryURL: stageDirectory,
            manifest: manifest,
            spritesheetURL: spritesheetURL
        )
    }

    private func isExpectedStageDirectory(_ directory: URL, for stage: CustomPetStage) -> Bool {
        let resolvedRoot = rootDirectory.resolvingSymlinksInPath().standardizedFileURL
        let expectedDirectory = resolvedRoot
            .appendingPathComponent(stage.directoryName, isDirectory: true)
            .standardizedFileURL
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        return resolvedDirectory.path == expectedDirectory.path
    }

    private func isValid(manifest: CodexPetManifest) -> Bool {
        !manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !manifest.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !manifest.spritesheetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func safeSpritesheetURL(path: String, inside stageDirectory: URL) -> URL? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathValue = trimmedPath as NSString
        guard !trimmedPath.isEmpty,
              !pathValue.isAbsolutePath,
              !trimmedPath.hasPrefix("~"),
              !pathValue.pathComponents.contains(".."),
              URL(fileURLWithPath: trimmedPath).pathExtension.lowercased() == "webp" else {
            return nil
        }

        let resolvedDirectory = stageDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let resolvedCandidate = stageDirectory
            .appendingPathComponent(trimmedPath, isDirectory: false)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let directoryPrefix = resolvedDirectory.path.hasSuffix("/")
            ? resolvedDirectory.path
            : resolvedDirectory.path + "/"

        guard resolvedCandidate.path.hasPrefix(directoryPrefix) else {
            return nil
        }

        return resolvedCandidate
    }
}

enum PetAtlasSourceKind: Hashable {
    case bundled(PetForm)
    case custom(CustomPetStage)
}

struct PetFrameKey: Hashable {
    let state: PetAtlasState
    let column: Int
    let source: PetAtlasSourceKind
}

enum PetAtlasValidator {
    static func loadValidatedWebP(at url: URL) -> CGImage? {
        guard url.pathExtension.lowercased() == "webp",
              let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceType = CGImageSourceGetType(imageSource),
              sourceType as String == UTType.webP.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width == PetAtlasSpec.atlasWidth,
              height == PetAtlasSpec.atlasHeight,
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              isValidAtlas(image) else {
            return nil
        }

        return image
    }

    static func isValidAtlas(_ image: CGImage) -> Bool {
        guard image.width == PetAtlasSpec.atlasWidth,
              image.height == PetAtlasSpec.atlasHeight else {
            return false
        }

        for state in PetAtlasState.allCases {
            let visibleColumnCount = PetAtlasSpec.visibleColumnCount(for: state)
            guard let rowImage = image.cropping(
                to: CGRect(
                    x: 0,
                    y: state.row * PetAtlasSpec.cellHeight,
                    width: PetAtlasSpec.atlasWidth,
                    height: PetAtlasSpec.cellHeight
                )
            ), let columnVisibility = visibleColumns(in: rowImage) else {
                return false
            }

            for column in 0..<visibleColumnCount where !columnVisibility[column] {
                return false
            }
            for column in visibleColumnCount..<PetAtlasSpec.columns where columnVisibility[column] {
                return false
            }
        }

        return true
    }

    private static func visibleColumns(in image: CGImage) -> [Bool]? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drewImage else {
            return nil
        }

        var result = [Bool](repeating: false, count: PetAtlasSpec.columns)
        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width where pixels[rowOffset + x * bytesPerPixel + 3] > 0 {
                result[min(x / PetAtlasSpec.cellWidth, PetAtlasSpec.columns - 1)] = true
            }
        }
        return result
    }
}

private enum CustomPetAtlasLoad {
    case valid(CGImage)
    case invalid
}

final class PetAtlasRepository {
    static let bundledAssetName = "FurinaPetSpritesheet"
    static let shared = PetAtlasRepository(catalog: .shared)

    private let catalog: CustomPetCatalog
    private let bundledImageProvider: () -> CGImage?
    private var bundledSpriteSheet: CGImage?
    private var customLoads: [CustomPetStage: CustomPetAtlasLoad] = [:]
    private var frameCache: [PetFrameKey: NSImage] = [:]
    private let frameCacheLimit = 180

    init(
        catalog: CustomPetCatalog,
        bundledImageProvider: @escaping () -> CGImage? = PetAtlasRepository.loadBundledImage
    ) {
        self.catalog = catalog
        self.bundledImageProvider = bundledImageProvider
    }

    func image(for state: PetAtlasState, frame: Int, form: PetForm) -> NSImage? {
        let column = PetAtlasSpec.normalizedFrameIndex(frame, for: state)
        let source = sourceKind(for: form)
        let key = PetFrameKey(state: state, column: column, source: source)

        if let cached = frameCache[key] {
            return cached
        }

        let sheet: CGImage?
        switch source {
        case .custom(let stage):
            sheet = customImage(for: stage)
        case .bundled:
            sheet = bundledImage()
        }

        guard let sheet else {
            return nil
        }

        let cropRect = CGRect(
            x: column * PetAtlasSpec.cellWidth,
            y: state.row * PetAtlasSpec.cellHeight,
            width: PetAtlasSpec.cellWidth,
            height: PetAtlasSpec.cellHeight
        )
        guard let croppedFrame = sheet.cropping(to: cropRect) else {
            return nil
        }

        let frameImage: CGImage
        switch source {
        case .custom:
            frameImage = croppedFrame
        case .bundled:
            frameImage = FurinaPetRecoloring.recoloredImage(croppedFrame, form: form)
        }

        let image = NSImage(
            cgImage: frameImage,
            size: NSSize(width: PetAtlasSpec.cellWidth, height: PetAtlasSpec.cellHeight)
        )

        if frameCache.count >= frameCacheLimit {
            frameCache.removeAll(keepingCapacity: true)
        }
        frameCache[key] = image
        return image
    }

    func sourceKind(for form: PetForm) -> PetAtlasSourceKind {
        let stage = CustomPetStage.stage(for: form)
        if customImage(for: stage) != nil {
            return .custom(stage)
        }

        if stage != .stage1, customImage(for: .stage1) != nil {
            return .custom(.stage1)
        }

        return .bundled(form)
    }

    private func customImage(for stage: CustomPetStage) -> CGImage? {
        if let existing = customLoads[stage] {
            switch existing {
            case .valid(let image): return image
            case .invalid: return nil
            }
        }

        guard let package = catalog.packages[stage],
              let image = PetAtlasValidator.loadValidatedWebP(at: package.spritesheetURL) else {
            customLoads[stage] = .invalid
            return nil
        }

        customLoads[stage] = .valid(image)
        return image
    }

    private func bundledImage() -> CGImage? {
        if let bundledSpriteSheet {
            return bundledSpriteSheet
        }

        let image = bundledImageProvider()
        bundledSpriteSheet = image
        return image
    }

    private static func loadBundledImage() -> CGImage? {
        guard let dataAsset = NSDataAsset(name: bundledAssetName),
              let imageSource = CGImageSourceCreateWithData(dataAsset.data as CFData, nil) else {
            return nil
        }

        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    }
}
