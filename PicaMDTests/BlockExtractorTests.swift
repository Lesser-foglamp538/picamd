import XCTest
@testable import PicaMD

final class BlockExtractorTests: XCTestCase {

    func testExtractsTable() {
        let source = """
        Intro paragraph.

        | A | B | C |
        |---|:-:|--:|
        | 1 | 2 | 3 |
        | 4 | 5 | 6 |

        Trailing paragraph.
        """
        let blocks = BlockExtractor.extract(from: source)
        let tables = blocks.filter { $0.kind == .table }
        XCTAssertEqual(tables.count, 1, "Expected exactly one table block")
        guard let parsed = tables.first?.parseTable() else {
            XCTFail("Failed to parse the table")
            return
        }
        XCTAssertEqual(parsed.headers, ["A", "B", "C"])
        XCTAssertEqual(parsed.rows.count, 2)
        XCTAssertEqual(parsed.rows.first, ["1", "2", "3"])
        XCTAssertEqual(parsed.alignments.count, 3)
        XCTAssertEqual(parsed.alignments[1], .center)
        XCTAssertEqual(parsed.alignments[2], .right)
    }

    func testIgnoresNonTablePipes() {
        let source = """
        A line with a | pipe but no separator below it.
        Just text with | another | pipe.
        """
        let blocks = BlockExtractor.extract(from: source)
        XCTAssertTrue(blocks.filter { $0.kind == .table }.isEmpty,
                      "Should not detect a table without a separator row")
    }

    func testExtractsMathBlock() {
        let source = """
        Intro.

        $$
        E = mc^2
        $$

        Outro.
        """
        let blocks = BlockExtractor.extract(from: source)
        let maths = blocks.filter { $0.kind == .mathBlock }
        XCTAssertEqual(maths.count, 1)
        XCTAssertTrue(maths.first?.payload.contains("E = mc^2") == true)
    }

    func testExtractsMermaidFence() {
        let source = """
        ```mermaid
        graph TD
        A --> B
        ```
        """
        let blocks = BlockExtractor.extract(from: source)
        let mermaids = blocks.filter { $0.kind == .mermaid }
        XCTAssertEqual(mermaids.count, 1)
        XCTAssertTrue(mermaids.first?.payload.contains("graph TD") == true)
    }

    func testExtractsBlockLevelImage() {
        let source = """
        Some intro.

        ![caption](./assets/photo.png)

        Some outro.
        """
        let blocks = BlockExtractor.extract(from: source)
        let images = blocks.filter { $0.kind == .image }
        XCTAssertEqual(images.count, 1)
    }

    func testInlineImageIsNotExtractedAsBlock() {
        let source = "Inline ![](url) here, not a block."
        let blocks = BlockExtractor.extract(from: source)
        XCTAssertTrue(blocks.filter { $0.kind == .image }.isEmpty,
                      "Inline image should not be extracted as a block")
    }

    func testBlocksAreSortedByLocation() {
        let source = """
        ```mermaid
        a --> b
        ```

        | A | B |
        |---|---|
        | 1 | 2 |

        $$
        x = 1
        $$
        """
        let blocks = BlockExtractor.extract(from: source)
        for i in 1..<blocks.count {
            XCTAssertLessThan(blocks[i - 1].range.location,
                              blocks[i].range.location,
                              "Blocks must come back sorted by location")
        }
    }
}
