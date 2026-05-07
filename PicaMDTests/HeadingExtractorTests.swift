import XCTest
@testable import PicaMD

final class HeadingExtractorTests: XCTestCase {

    func testExtractsAllHeadingLevels() {
        let source = """
        # H1
        ## H2
        ### H3
        #### H4
        ##### H5
        ###### H6
        Body
        """
        let h = HeadingExtractor.extract(from: source)
        XCTAssertEqual(h.map(\.level), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(h.map(\.text), ["H1", "H2", "H3", "H4", "H5", "H6"])
    }

    func testIgnoresHeadingsInFencedCodeBlocks() {
        let source = """
        # Real heading

        ```bash
        # this is a comment, not a heading
        echo "ok"
        ```

        ## Another real heading
        """
        let h = HeadingExtractor.extract(from: source)
        XCTAssertEqual(h.map(\.text), ["Real heading", "Another real heading"])
    }

    func testIgnoresHashLinesWithoutSpace() {
        // CommonMark: `#hello` (no space after #) is NOT a heading
        let source = """
        #not-a-heading
        # actual
        """
        let h = HeadingExtractor.extract(from: source)
        XCTAssertEqual(h.map(\.text), ["actual"])
    }

    func testStripsTrailingClosingHashes() {
        let source = "## Title ##"
        let h = HeadingExtractor.extract(from: source)
        XCTAssertEqual(h.first?.text, "Title")
    }

    func testIDsAreMonotonic() {
        let source = "# A\n# B\n# C"
        let h = HeadingExtractor.extract(from: source)
        XCTAssertEqual(h.map(\.id), [0, 1, 2])
    }

    func testTitleLocationPointsAtFirstLetter() {
        let source = "## Section title"
        let h = HeadingExtractor.extract(from: source)
        XCTAssertEqual(h.first?.titleLocation, 3)  // skips "## "
    }

    func testEmptyDocumentReturnsEmpty() {
        XCTAssertEqual(HeadingExtractor.extract(from: "").count, 0)
    }
}
