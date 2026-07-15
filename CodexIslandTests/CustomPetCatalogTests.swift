import AppKit
import CoreGraphics
import ImageIO
import XCTest
@testable import CodexIsland

final class CustomPetCatalogTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDown() {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        super.tearDown()
    }

    func testCreatesAllStageDirectoriesWithoutOverwritingUserFiles() throws {
        let root = makeTemporaryRoot()
        let catalog = CustomPetCatalog(rootDirectory: root)

        XCTAssertEqual(CustomPetStage.allCases.count, 10)
        for stage in CustomPetStage.allCases {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: catalog.directory(for: stage).path,
                    isDirectory: &isDirectory
                )
            )
            XCTAssertTrue(isDirectory.boolValue)
        }

        let marker = catalog.directory(for: .stage4).appendingPathComponent("user-note.txt")
        try Data("keep me".utf8).write(to: marker)
        _ = CustomPetCatalog(rootDirectory: root)
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "keep me")
    }

    func testLevelsMapToTenStagesAndNinetyThroughOneHundredShareLastStage() {
        XCTAssertEqual(CustomPetStage.stage(forLevel: 0), .stage1)
        XCTAssertEqual(CustomPetStage.stage(forLevel: 9), .stage1)
        XCTAssertEqual(CustomPetStage.stage(forLevel: 10), .stage2)
        XCTAssertEqual(CustomPetStage.stage(forLevel: 89), .stage9)
        XCTAssertEqual(CustomPetStage.stage(forLevel: 90), .stage10)
        XCTAssertEqual(CustomPetStage.stage(forLevel: 100), .stage10)
        XCTAssertEqual(CustomPetStage.stage(for: .hairPink), .stage10)
        XCTAssertEqual(CustomPetStage.stage(for: .fullPink), .stage10)
    }

    func testScansValidPackageAndRejectsMissingOrMalformedManifest() throws {
        let root = makeTemporaryRoot()
        let initialCatalog = CustomPetCatalog(rootDirectory: root)
        try writeValidPackage(stage: .stage1, catalog: initialCatalog)
        try Data("not-json".utf8).write(
            to: initialCatalog.directory(for: .stage2).appendingPathComponent("pet.json")
        )
        try writeManifest(
            CodexPetManifest(
                id: "",
                displayName: "Missing ID",
                description: "Invalid manifest.",
                spritesheetPath: "spritesheet.webp"
            ),
            stage: .stage3,
            catalog: initialCatalog
        )

        let scannedCatalog = CustomPetCatalog(rootDirectory: root)
        XCTAssertNotNil(scannedCatalog.packages[.stage1])
        XCTAssertNil(scannedCatalog.packages[.stage2])
        XCTAssertNil(scannedCatalog.packages[.stage3])
        XCTAssertNil(scannedCatalog.packages[.stage4])
    }

    func testScansAndLoadsPNGPackage() throws {
        let root = makeTemporaryRoot()
        let initialCatalog = CustomPetCatalog(rootDirectory: root)
        try writeManifest(
            manifest(path: "spritesheet.png"),
            stage: .stage1,
            catalog: initialCatalog
        )
        try pngSpritesheetData().write(
            to: initialCatalog.directory(for: .stage1).appendingPathComponent("spritesheet.png")
        )

        let catalog = CustomPetCatalog(rootDirectory: root)
        let repository = PetAtlasRepository(catalog: catalog)
        XCTAssertEqual(repository.sourceKind(for: .original), .custom(.stage1))
        XCTAssertNotNil(repository.image(for: .idle, frame: 7, form: .original))
    }

    func testRejectsUnsupportedExtensionAndMismatchedImageEncoding() throws {
        let root = makeTemporaryRoot()
        let initialCatalog = CustomPetCatalog(rootDirectory: root)

        try writeManifest(
            manifest(path: "spritesheet.gif"),
            stage: .stage1,
            catalog: initialCatalog
        )
        try bundledSpritesheetData().write(
            to: initialCatalog.directory(for: .stage1).appendingPathComponent("spritesheet.gif")
        )

        try writeManifest(
            manifest(path: "spritesheet.png"),
            stage: .stage2,
            catalog: initialCatalog
        )
        try bundledSpritesheetData().write(
            to: initialCatalog.directory(for: .stage2).appendingPathComponent("spritesheet.png")
        )

        let catalog = CustomPetCatalog(rootDirectory: root)
        let repository = PetAtlasRepository(catalog: catalog)
        XCTAssertNil(catalog.packages[.stage1])
        XCTAssertEqual(repository.sourceKind(for: .shoesPink), .bundled(.shoesPink))
    }

    func testRejectsAbsoluteTraversalAndOutsideSymlinkSpritesheetPaths() throws {
        let root = makeTemporaryRoot()
        let initialCatalog = CustomPetCatalog(rootDirectory: root)
        let outsideWebP = root.deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString).webp")
        temporaryRoots.append(outsideWebP)
        try bundledSpritesheetData().write(to: outsideWebP)

        try writeManifest(manifest(path: outsideWebP.path), stage: .stage1, catalog: initialCatalog)
        try writeManifest(manifest(path: "../outside.webp"), stage: .stage2, catalog: initialCatalog)

        let symlink = initialCatalog.directory(for: .stage3)
            .appendingPathComponent("spritesheet.webp")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outsideWebP)
        try writeManifest(manifest(path: "spritesheet.webp"), stage: .stage3, catalog: initialCatalog)

        let outsideStage = root.deletingLastPathComponent()
            .appendingPathComponent("outside-stage-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(outsideStage)
        try FileManager.default.createDirectory(at: outsideStage, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest(path: "spritesheet.webp"))
            .write(to: outsideStage.appendingPathComponent("pet.json"))
        try bundledSpritesheetData().write(
            to: outsideStage.appendingPathComponent("spritesheet.webp")
        )
        let stage4 = initialCatalog.directory(for: .stage4)
        try FileManager.default.removeItem(at: stage4)
        try FileManager.default.createSymbolicLink(at: stage4, withDestinationURL: outsideStage)

        let scannedCatalog = CustomPetCatalog(rootDirectory: root)
        XCTAssertNil(scannedCatalog.packages[.stage1])
        XCTAssertNil(scannedCatalog.packages[.stage2])
        XCTAssertNil(scannedCatalog.packages[.stage3])
        XCTAssertNil(scannedCatalog.packages[.stage4])
    }

    func testAtlasValidatorAllowsAnyTransparentFrameSlotsWithinEightColumns() throws {
        let fullyTransparent = try makeAtlas()
        XCTAssertTrue(PetAtlasValidator.isValidAtlas(fullyTransparent))
        XCTAssertEqual(
            PetAtlasValidator.nonTransparentColumns(in: fullyTransparent, for: .idle),
            []
        )

        let seventhAndEighthFrames = try makeAtlas(filledCells: [(.idle, 6), (.idle, 7)])
        XCTAssertTrue(PetAtlasValidator.isValidAtlas(seventhAndEighthFrames))
        XCTAssertEqual(
            PetAtlasValidator.nonTransparentColumns(in: seventhAndEighthFrames, for: .idle),
            [6, 7]
        )

        let internalTransparentFrame = try makeAtlas(filledCells: [(.running, 0), (.running, 7)])
        XCTAssertTrue(PetAtlasValidator.isValidAtlas(internalTransparentFrame))
        XCTAssertEqual(
            PetAtlasValidator.nonTransparentColumns(in: internalTransparentFrame, for: .running),
            [0, 7]
        )
    }

    func testAtlasValidatorRequiresEightColumnsAndAtLeastNineAlignedRows() throws {
        XCTAssertTrue(PetAtlasValidator.isValidAtlas(try makeAtlas(rowCount: 9)))
        XCTAssertTrue(PetAtlasValidator.isValidAtlas(try makeAtlas(rowCount: 11)))
        XCTAssertFalse(PetAtlasValidator.isValidAtlas(try makeAtlas(rowCount: 8)))
        XCTAssertFalse(
            PetAtlasValidator.isValidAtlas(
                try makeAtlas(width: PetAtlasSpec.atlasWidth - PetAtlasSpec.cellWidth)
            )
        )
        XCTAssertFalse(
            PetAtlasValidator.isValidAtlas(
                try makeAtlas(height: PetAtlasSpec.atlasHeight + 1)
            )
        )
    }

    func testEmptyCatalogUsesEachFormsBundledDefaultPet() {
        let repository = PetAtlasRepository(
            catalog: CustomPetCatalog(rootDirectory: makeTemporaryRoot())
        )

        for form in PetForm.allCases {
            XCTAssertEqual(repository.sourceKind(for: form), .bundled(form))
        }
    }

    func testValidFirstStageIsInheritedByMissingOrCorruptLaterStages() throws {
        let root = makeTemporaryRoot()
        let initialCatalog = CustomPetCatalog(rootDirectory: root)
        try writeValidPackage(stage: .stage1, catalog: initialCatalog)
        try writeManifest(manifest(path: "broken.webp"), stage: .stage2, catalog: initialCatalog)
        try Data("broken".utf8).write(
            to: initialCatalog.directory(for: .stage2).appendingPathComponent("broken.webp")
        )

        let catalog = CustomPetCatalog(rootDirectory: root)
        let repository = PetAtlasRepository(catalog: catalog)
        XCTAssertEqual(repository.sourceKind(for: .original), .custom(.stage1))
        XCTAssertEqual(repository.sourceKind(for: .shoesPink), .custom(.stage1))
        XCTAssertEqual(repository.sourceKind(for: .legsPink), .custom(.stage1))
        XCTAssertEqual(repository.sourceKind(for: .fullPink), .custom(.stage1))
    }

    func testCustomAtlasesDeriveFrameCountsWhileBundledCountsStayUnchanged() throws {
        let root = makeTemporaryRoot()
        let catalog = CustomPetCatalog(rootDirectory: root)
        try writeValidPackage(stage: .stage1, catalog: catalog)

        let repository = PetAtlasRepository(catalog: catalog)
        repository.reloadCustomPets()

        XCTAssertEqual(repository.frameCount(for: .idle, form: .original), 6)
        XCTAssertEqual(repository.frameCount(for: .waving, form: .original), 4)
        XCTAssertEqual(repository.frameCount(for: .jumping, form: .original), 5)
        XCTAssertNotNil(repository.image(for: .idle, frame: 7, form: .original))

        XCTAssertEqual(repository.frameCount(for: .idle, form: .shoesPink), 6)

        let bundledRepository = PetAtlasRepository(
            catalog: CustomPetCatalog(rootDirectory: makeTemporaryRoot())
        )
        XCTAssertEqual(bundledRepository.frameCount(for: .idle, form: .original), 6)
        XCTAssertEqual(bundledRepository.frameCount(for: .waving, form: .original), 4)
        XCTAssertEqual(bundledRepository.frameCount(for: .jumping, form: .original), 5)
        XCTAssertEqual(bundledRepository.frameCount(for: .runningRight, form: .original), 8)
    }

    func testCustomAnimationSkipsTrailingAndInternalTransparentSlots() throws {
        let root = makeTemporaryRoot()
        let catalog = CustomPetCatalog(rootDirectory: root)
        let atlas = try makeAtlas(filledCells: [(.idle, 0), (.idle, 2), (.idle, 7)])
        try writeManifest(
            manifest(path: "spritesheet.png"),
            stage: .stage1,
            catalog: catalog
        )
        try pngData(from: atlas).write(
            to: catalog.directory(for: .stage1).appendingPathComponent("spritesheet.png")
        )

        let repository = PetAtlasRepository(catalog: CustomPetCatalog(rootDirectory: root))
        XCTAssertEqual(repository.sourceKind(for: .original), .custom(.stage1))
        XCTAssertEqual(repository.frameColumns(for: .idle, form: .original), [0, 2, 7])
        XCTAssertEqual(repository.frameCount(for: .idle, form: .original), 3)

        XCTAssertEqual(repository.frameColumns(for: .running, form: .original), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(repository.frameCount(for: .running, form: .original), 6)
    }

    func testLevelElevenUsesFirstStageWhenSecondStageIsMissing() throws {
        let root = makeTemporaryRoot()
        let catalog = CustomPetCatalog(rootDirectory: root)
        try writeValidPackage(stage: .stage1, catalog: catalog)

        let repository = PetAtlasRepository(catalog: catalog)
        repository.reloadCustomPets()

        let form = PetForm.form(for: 11)
        XCTAssertEqual(form, .shoesPink)
        XCTAssertEqual(repository.sourceKind(for: form), .custom(.stage1))
    }

    func testStartupReloadFindsPackagesAddedAfterCatalogInitialization() throws {
        let root = makeTemporaryRoot()
        let catalog = CustomPetCatalog(rootDirectory: root)
        let repository = PetAtlasRepository(catalog: catalog)
        XCTAssertEqual(repository.sourceKind(for: .shoesPink), .bundled(.shoesPink))

        try writeValidPackage(stage: .stage1, catalog: catalog)
        repository.reloadCustomPets()

        XCTAssertEqual(repository.sourceKind(for: .shoesPink), .custom(.stage1))
    }

    func testConfiguredLaterStageWinsWhileOtherMissingStagesUseBundledDefaultsWithoutStageOne() throws {
        let root = makeTemporaryRoot()
        let initialCatalog = CustomPetCatalog(rootDirectory: root)
        try writeValidPackage(stage: .stage2, catalog: initialCatalog)

        let repository = PetAtlasRepository(
            catalog: CustomPetCatalog(rootDirectory: root)
        )
        XCTAssertEqual(repository.sourceKind(for: .original), .bundled(.original))
        XCTAssertEqual(repository.sourceKind(for: .shoesPink), .custom(.stage2))
        XCTAssertEqual(repository.sourceKind(for: .legsPink), .bundled(.legsPink))
    }

    func testCustomAtlasDoesNotReceiveFurinaStageRecoloring() throws {
        let root = makeTemporaryRoot()
        let initialCatalog = CustomPetCatalog(rootDirectory: root)
        try writeValidPackage(stage: .stage10, catalog: initialCatalog)
        let repository = PetAtlasRepository(catalog: CustomPetCatalog(rootDirectory: root))

        guard let hair = repository.image(for: .idle, frame: 0, form: .hairPink),
              let fullPink = repository.image(for: .idle, frame: 0, form: .fullPink),
              let hairData = rgbaData(from: hair),
              let fullPinkData = rgbaData(from: fullPink) else {
            return XCTFail("Expected custom frames")
        }

        XCTAssertEqual(repository.sourceKind(for: .hairPink), .custom(.stage10))
        XCTAssertEqual(hairData, fullPinkData)
    }

    func testFilesAddedDuringRuntimeRequireNewCatalogToLoad() throws {
        let root = makeTemporaryRoot()
        let runningCatalog = CustomPetCatalog(rootDirectory: root)
        let runningRepository = PetAtlasRepository(catalog: runningCatalog)
        XCTAssertEqual(runningRepository.sourceKind(for: .original), .bundled(.original))

        try writeValidPackage(stage: .stage1, catalog: runningCatalog)
        XCTAssertEqual(runningRepository.sourceKind(for: .original), .bundled(.original))

        let restartedRepository = PetAtlasRepository(
            catalog: CustomPetCatalog(rootDirectory: root)
        )
        XCTAssertEqual(restartedRepository.sourceKind(for: .original), .custom(.stage1))
    }

    func testExternalPetPackageWhenConfigured() throws {
        let configuredPath = ProcessInfo.processInfo.environment["CODEX_ISLAND_TEST_PET_PACKAGE"]
        let fallbackPath = "/tmp/CodexIslandExternalPetFixture"
        let packagePath = [configuredPath, fallbackPath]
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0) }
        guard let packagePath else {
            throw XCTSkip("Set CODEX_ISLAND_TEST_PET_PACKAGE to run the external pet integration test.")
        }

        let sourceDirectory = URL(fileURLWithPath: packagePath, isDirectory: true)
        let sourceManifest = try JSONDecoder().decode(
            CodexPetManifest.self,
            from: Data(contentsOf: sourceDirectory.appendingPathComponent("pet.json"))
        )
        let root = makeTemporaryRoot()
        let initialCatalog = CustomPetCatalog(rootDirectory: root)
        let stageDirectory = initialCatalog.directory(for: .stage1)
        try FileManager.default.copyItem(
            at: sourceDirectory.appendingPathComponent("pet.json"),
            to: stageDirectory.appendingPathComponent("pet.json")
        )
        try FileManager.default.copyItem(
            at: sourceDirectory.appendingPathComponent(sourceManifest.spritesheetPath),
            to: stageDirectory.appendingPathComponent(sourceManifest.spritesheetPath)
        )

        let catalog = CustomPetCatalog(rootDirectory: root)
        let repository = PetAtlasRepository(catalog: catalog)
        XCTAssertEqual(catalog.packages[.stage1]?.manifest.id, sourceManifest.id)
        for form in PetForm.allCases {
            XCTAssertEqual(repository.sourceKind(for: form), .custom(.stage1))
        }
        XCTAssertNotNil(repository.image(for: .idle, frame: 0, form: .fullPink))

        guard let image = PetAtlasValidator.loadValidatedImage(
            at: stageDirectory.appendingPathComponent(sourceManifest.spritesheetPath)
        ) else {
            return XCTFail("Expected external atlas to load")
        }
        for state in PetAtlasState.allCases {
            let detectedColumns = try XCTUnwrap(
                PetAtlasValidator.nonTransparentColumns(in: image, for: state)
            )
            let expectedColumns = detectedColumns.isEmpty
                ? Array(0..<PetAtlasSpec.bundledFrameCount(for: state))
                : detectedColumns
            XCTAssertEqual(
                repository.frameColumns(for: state, form: .original),
                expectedColumns
            )
        }
    }

    private func makeTemporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexIslandCustomPetTests-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        return root
    }

    private func manifest(path: String) -> CodexPetManifest {
        CodexPetManifest(
            id: "test-pet",
            displayName: "Test Pet",
            description: "A test Codex pet.",
            spritesheetPath: path
        )
    }

    private func writeValidPackage(stage: CustomPetStage, catalog: CustomPetCatalog) throws {
        try writeManifest(manifest(path: "spritesheet.webp"), stage: stage, catalog: catalog)
        try bundledSpritesheetData().write(
            to: catalog.directory(for: stage).appendingPathComponent("spritesheet.webp")
        )
    }

    private func writeManifest(
        _ manifest: CodexPetManifest,
        stage: CustomPetStage,
        catalog: CustomPetCatalog
    ) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: catalog.directory(for: stage).appendingPathComponent("pet.json"))
    }

    private func bundledSpritesheetData() throws -> Data {
        guard let asset = NSDataAsset(name: PetAtlasRepository.bundledAssetName) else {
            throw TestError.missingBundledAtlas
        }
        return asset.data
    }

    private func pngSpritesheetData() throws -> Data {
        let webPData = try bundledSpritesheetData()
        guard let source = CGImageSourceCreateWithData(webPData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw TestError.couldNotCreateImage
        }
        return data
    }

    private func pngData(from image: CGImage) throws -> Data {
        guard let data = NSBitmapImageRep(cgImage: image).representation(
            using: .png,
            properties: [:]
        ) else {
            throw TestError.couldNotCreateImage
        }
        return data
    }

    private func makeAtlas(
        width: Int = PetAtlasSpec.atlasWidth,
        height: Int? = nil,
        rowCount: Int = PetAtlasSpec.rows,
        filledCells: [(PetAtlasState, Int)] = []
    ) throws -> CGImage {
        let resolvedHeight = height ?? rowCount * PetAtlasSpec.cellHeight
        guard let context = CGContext(
            data: nil,
            width: width,
            height: resolvedHeight,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestError.couldNotCreateImage
        }

        context.clear(
            CGRect(x: 0, y: 0, width: width, height: resolvedHeight)
        )
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.5, alpha: 1))

        for filledCell in filledCells {
            fillTestPixel(
                state: filledCell.0,
                column: filledCell.1,
                atlasHeight: resolvedHeight,
                context: context
            )
        }

        guard let image = context.makeImage() else {
            throw TestError.couldNotCreateImage
        }
        return image
    }

    private func fillTestPixel(
        state: PetAtlasState,
        column: Int,
        atlasHeight: Int,
        context: CGContext
    ) {
        context.fill(
            CGRect(
                x: column * PetAtlasSpec.cellWidth + 8,
                y: atlasHeight - (state.row + 1) * PetAtlasSpec.cellHeight + 8,
                width: 4,
                height: 4
            )
        )
    }

    private func rgbaData(from image: NSImage) -> [UInt8]? {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }

        let bytesPerRow = cgImage.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * cgImage.height)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
            )
            return true
        }
        return drew ? pixels : nil
    }

    private enum TestError: Error {
        case missingBundledAtlas
        case couldNotCreateImage
    }
}
