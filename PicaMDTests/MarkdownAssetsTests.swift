import XCTest
@testable import PicaMD

final class MarkdownAssetsTests: XCTestCase {

    private var tempDir: URL!
    private var docURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PicaMDAssetsTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        docURL = tempDir.appendingPathComponent("note.md")
        try "# test".data(using: .utf8)?.write(to: docURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testCopyImageCreatesAssetsFolder() throws {
        // Create a fake source file
        let source = tempDir.appendingPathComponent("photo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)  // PNG magic header

        let saved = try MarkdownAssets.copyImage(from: source, nextTo: docURL)
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.markdownPath, "./assets/photo.png")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("assets/photo.png").path))
        XCTAssertEqual(saved?.altText, "photo")
    }

    func testCopyImageDeduplicatesOnNameClash() throws {
        let source1 = tempDir.appendingPathComponent("photo.png")
        let source2 = tempDir.appendingPathComponent("photo-other.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source1)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source2)

        let first = try MarkdownAssets.copyImage(from: source1, nextTo: docURL)
        // Rename source2 to also be `photo.png` (different content)
        let temp = tempDir.appendingPathComponent("photo.png")
        try? FileManager.default.removeItem(at: temp)
        try FileManager.default.copyItem(at: source2, to: temp)

        let second = try MarkdownAssets.copyImage(from: temp, nextTo: docURL)
        XCTAssertEqual(first?.markdownPath, "./assets/photo.png")
        XCTAssertEqual(second?.markdownPath, "./assets/photo-2.png")
    }

    func testSaveImageDataWritesPNG() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let saved = try MarkdownAssets.saveImageData(png,
                                                     kind: .screenshot,
                                                     nextTo: docURL)
        XCTAssertNotNil(saved)
        XCTAssertTrue(saved!.markdownPath.hasPrefix("./assets/Screenshot-"))
        XCTAssertTrue(saved!.markdownPath.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved!.absoluteURL.path))
    }

    func testNilDocumentURLReturnsNil() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let saved = try MarkdownAssets.saveImageData(png, kind: .pasted, nextTo: nil)
        XCTAssertNil(saved)
    }

    func testMarkdownSyntaxFormat() {
        let img = MarkdownAssets.SavedImage(
            absoluteURL: docURL,
            markdownPath: "./assets/photo.png",
            altText: "Cover image"
        )
        XCTAssertEqual(MarkdownAssets.markdownSyntax(for: img),
                       "![Cover image](./assets/photo.png)")
    }
}
