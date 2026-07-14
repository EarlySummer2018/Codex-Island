import AppKit
import CoreGraphics
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

    func testAtlasValidatorEnforcesGeometryRequiredFramesAndTransparentUnusedCells() throws {
        let valid = try makeContractAtlas()
        XCTAssertTrue(PetAtlasValidator.isValidAtlas(valid))

        let missingRequired = try makeContractAtlas(blankCell: (.idle, 0))
        XCTAssertFalse(PetAtlasValidator.isValidAtlas(missingRequired))

        let nonTransparentUnused = try makeContractAtlas(filledUnusedCell: (.idle, 7))
        XCTAssertFalse(PetAtlasValidator.isValidAtlas(nonTransparentUnused))

        guard let wrongSize = valid.cropping(to: CGRect(x: 0, y: 0, width: 100, height: 100)) else {
            return XCTFail("Expected cropped image")
        }
        XCTAssertFalse(PetAtlasValidator.isValidAtlas(wrongSize))
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
        let root = makeTemporaryRoot()
        let initialCatalog = CustomPetCatalog(rootDirectory: root)
        let stageDirectory = initialCatalog.directory(for: .stage1)
        try FileManager.default.copyItem(
            at: sourceDirectory.appendingPathComponent("pet.json"),
            to: stageDirectory.appendingPathComponent("pet.json")
        )
        try FileManager.default.copyItem(
            at: sourceDirectory.appendingPathComponent("spritesheet.webp"),
            to: stageDirectory.appendingPathComponent("spritesheet.webp")
        )

        let catalog = CustomPetCatalog(rootDirectory: root)
        let repository = PetAtlasRepository(catalog: catalog)
        XCTAssertEqual(catalog.packages[.stage1]?.manifest.id, "ruby")
        for form in PetForm.allCases {
            XCTAssertEqual(repository.sourceKind(for: form), .custom(.stage1))
        }
        XCTAssertNotNil(repository.image(for: .idle, frame: 0, form: .fullPink))
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

    private func makeContractAtlas(
        blankCell: (PetAtlasState, Int)? = nil,
        filledUnusedCell: (PetAtlasState, Int)? = nil
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: PetAtlasSpec.atlasWidth,
            height: PetAtlasSpec.atlasHeight,
            bitsPerComponent: 8,
            bytesPerRow: PetAtlasSpec.atlasWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestError.couldNotCreateImage
        }

        context.clear(
            CGRect(x: 0, y: 0, width: PetAtlasSpec.atlasWidth, height: PetAtlasSpec.atlasHeight)
        )
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.5, alpha: 1))

        for state in PetAtlasState.allCases {
            for column in 0..<PetAtlasSpec.visibleColumnCount(for: state) {
                if blankCell?.0 == state, blankCell?.1 == column {
                    continue
                }
                fillTestPixel(state: state, column: column, context: context)
            }
        }

        if let filledUnusedCell {
            fillTestPixel(
                state: filledUnusedCell.0,
                column: filledUnusedCell.1,
                context: context
            )
        }

        guard let image = context.makeImage() else {
            throw TestError.couldNotCreateImage
        }
        return image
    }

    private func fillTestPixel(state: PetAtlasState, column: Int, context: CGContext) {
        context.fill(
            CGRect(
                x: column * PetAtlasSpec.cellWidth + 8,
                y: PetAtlasSpec.atlasHeight - (state.row + 1) * PetAtlasSpec.cellHeight + 8,
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
