import XCTest
@testable import PicaMD

final class FootnoteIndexTests: XCTestCase {

    func testEmptySource() {
        let idx = FootnoteIndex.build(from: "")
        XCTAssertTrue(idx.refs.isEmpty)
        XCTAssertTrue(idx.definitions.isEmpty)
    }

    func testNoFootnotes() {
        let idx = FootnoteIndex.build(from: "Just a plain paragraph.\n\nNo refs.")
        XCTAssertTrue(idx.refs.isEmpty)
        XCTAssertTrue(idx.definitions.isEmpty)
    }

    func testSingleRefAndDef() {
        let src = """
        Body text with a ref [^1] in it.

        [^1]: This is the definition.
        """
        let idx = FootnoteIndex.build(from: src)
        XCTAssertEqual(idx.refs.count, 1)
        XCTAssertEqual(idx.refs.first?.id, "1")
        XCTAssertEqual(idx.definitions["1"], "This is the definition.")
    }

    func testMultipleRefsAndDefs() {
        let src = """
        First [^a] and second [^b] and third [^a] (re-ref).

        [^a]: Apple.
        [^b]: Banana.
        """
        let idx = FootnoteIndex.build(from: src)
        XCTAssertEqual(idx.refs.count, 3)
        XCTAssertEqual(idx.refs.map(\.id), ["a", "b", "a"])
        XCTAssertEqual(idx.definitions["a"], "Apple.")
        XCTAssertEqual(idx.definitions["b"], "Banana.")
    }

    func testMultiLineDefinitionCollapses() {
        let src = """
        See [^x] for more.

        [^x]: First line of the def
            continues here
            and ends here.

        Next paragraph.
        """
        let idx = FootnoteIndex.build(from: src)
        // Expect the multi-line body to be joined into a single
        // whitespace-collapsed string and to stop at the blank line.
        XCTAssertEqual(idx.definitions["x"],
                        "First line of the def continues here and ends here.")
    }

    func testDefinitionStopsAtNextDefinition() {
        let src = """
        Refs: [^a] [^b].

        [^a]: First.
        [^b]: Second.
        """
        let idx = FootnoteIndex.build(from: src)
        XCTAssertEqual(idx.definitions["a"], "First.")
        XCTAssertEqual(idx.definitions["b"], "Second.")
    }

    func testRefAtCharIndex() {
        let src = "Hello [^foo] world."
        let idx = FootnoteIndex.build(from: src)
        // [^foo] starts at char 6, length 6
        XCTAssertNil(idx.ref(at: 5))
        XCTAssertNotNil(idx.ref(at: 6))      // start
        XCTAssertNotNil(idx.ref(at: 11))     // last char of `]`
        XCTAssertNil(idx.ref(at: 12))        // space after
        XCTAssertEqual(idx.ref(at: 7)?.id, "foo")
    }

    func testRefIdsCanContainPunctuationButNotBracket() {
        // Per CommonMark / pandoc, ids allow most chars except `]`.
        let src = "Cite [^smith-2024] here.\n\n[^smith-2024]: Smith, J. (2024)."
        let idx = FootnoteIndex.build(from: src)
        XCTAssertEqual(idx.refs.first?.id, "smith-2024")
        XCTAssertEqual(idx.definitions["smith-2024"], "Smith, J. (2024).")
    }

    func testIndexEqualityStableAcrossBuilds() {
        let src = "X [^1] Y\n\n[^1]: def"
        let a = FootnoteIndex.build(from: src)
        let b = FootnoteIndex.build(from: src)
        XCTAssertEqual(a, b)
    }
}
