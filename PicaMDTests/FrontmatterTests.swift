import XCTest
@testable import PicaMD

final class FrontmatterTests: XCTestCase {

    func testNoFrontmatter() {
        let fm = Frontmatter.build(from: "# Just a heading\n\nBody.")
        XCTAssertNil(fm.range)
        XCTAssertTrue(fm.scalars.isEmpty)
        XCTAssertTrue(fm.arrays.isEmpty)
    }

    func testNotAtTopOfDocument() {
        // Frontmatter only counts when it's literally the first thing.
        let fm = Frontmatter.build(from: "Some prose first.\n\n---\ntitle: Nope\n---\n")
        XCTAssertNil(fm.range)
    }

    func testScalarKeysAndQuotedValues() {
        let src = """
        ---
        title: My document
        date: 2026-04-01
        author: "Wittmann, Michael"
        slug: 'hello-world'
        ---
        Body.
        """
        let fm = Frontmatter.build(from: src)
        XCTAssertNotNil(fm.range)
        XCTAssertEqual(fm.title, "My document")
        XCTAssertEqual(fm.date, "2026-04-01")
        XCTAssertEqual(fm.scalars["author"], "Wittmann, Michael")
        XCTAssertEqual(fm.scalars["slug"], "hello-world")
    }

    func testInlineTagsArray() {
        let src = """
        ---
        title: Foo
        tags: [swift, macos, markdown]
        ---
        """
        let fm = Frontmatter.build(from: src)
        XCTAssertEqual(fm.tags, ["swift", "macos", "markdown"])
    }

    func testListStyleTags() {
        let src = """
        ---
        title: Bar
        tags:
          - swift
          - macos
          - markdown
        ---
        """
        let fm = Frontmatter.build(from: src)
        XCTAssertEqual(fm.tags, ["swift", "macos", "markdown"])
    }

    func testFallbacksOnNameAndCreated() {
        let src = """
        ---
        name: Untitled
        created: 2026-04-30
        ---
        """
        let fm = Frontmatter.build(from: src)
        XCTAssertEqual(fm.title, "Untitled")
        XCTAssertEqual(fm.date, "2026-04-30")
    }

    func testEmptyFrontmatterBlockIsHandled() {
        let src = "---\n---\n\nBody."
        let fm = Frontmatter.build(from: src)
        // Range is reported but no scalars/arrays
        XCTAssertNotNil(fm.range)
        XCTAssertTrue(fm.scalars.isEmpty)
        XCTAssertTrue(fm.arrays.isEmpty)
    }

    func testQuotedValuesAreUnquoted() {
        let src = """
        ---
        title: "Double-quoted"
        subtitle: 'Single-quoted'
        plain: no quotes here
        ---
        """
        let fm = Frontmatter.build(from: src)
        XCTAssertEqual(fm.scalars["title"], "Double-quoted")
        XCTAssertEqual(fm.scalars["subtitle"], "Single-quoted")
        XCTAssertEqual(fm.scalars["plain"], "no quotes here")
    }

    func testParseInlineArrayHandlesQuotedItems() {
        XCTAssertEqual(Frontmatter.parseInlineArray("[a, b, c]"), ["a", "b", "c"])
        XCTAssertEqual(Frontmatter.parseInlineArray("['a', \"b\", c]"), ["a", "b", "c"])
        XCTAssertEqual(Frontmatter.parseInlineArray("[]"), [])
    }
}
