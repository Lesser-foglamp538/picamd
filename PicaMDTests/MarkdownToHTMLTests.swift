import XCTest
@testable import PicaMD

final class MarkdownToHTMLTests: XCTestCase {

    // MARK: - Headings, paragraphs, basic structure

    func testHeadingsAndParagraph() {
        let md = """
        # Hello

        World text.

        ## Sub

        More.
        """
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<h1>Hello</h1>"))
        XCTAssertTrue(out.contains("<h2>Sub</h2>"))
        XCTAssertTrue(out.contains("<p>World text.</p>"))
    }

    func testTitleFromFrontmatter() {
        let md = """
        ---
        title: My Special Document
        ---

        # Heading inside

        Body.
        """
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<title>My Special Document</title>"))
        // Frontmatter itself shouldn't appear in the body.
        XCTAssertFalse(out.contains("title:"))
    }

    func testTitleFallsBackToFirstHeading() {
        let md = "# First H\n\nSome text."
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<title>First H</title>"))
    }

    func testTitleFallsBackToUntitled() {
        let md = "Just plain text, no heading."
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<title>Untitled</title>"))
    }

    // MARK: - Inline formatting

    func testEmphasisAndStrong() {
        let md = "*italic* **bold** ***both***"
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<em>italic</em>"))
        XCTAssertTrue(out.contains("<strong>bold</strong>"))
    }

    func testInlineCode() {
        let md = "Use `swift build` here."
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<code>swift build</code>"))
    }

    func testStrikethrough() {
        let md = "~~old way~~"
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<s>old way</s>"))
    }

    func testHighlightConvertsToMark() {
        let md = "This is ==highlighted== text."
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<mark>highlighted</mark>"))
    }

    func testLink() {
        let md = "[Apple](https://apple.com)"
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<a href=\"https://apple.com\">Apple</a>"))
    }

    func testHTMLEscapeInText() {
        // `<` in plain text should NEVER be passed through as raw HTML.
        let md = "Compare a < b and 5 > 3."
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("a &lt; b"))
        XCTAssertTrue(out.contains("5 &gt; 3"))
    }

    // MARK: - Block-level

    func testBlockquote() {
        let md = "> Quoted line."
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<blockquote>"))
        XCTAssertTrue(out.contains("Quoted line."))
    }

    func testFencedCodeBlockWithLanguage() {
        let md = "```swift\nlet x = 1\n```"
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<pre><code class=\"language-swift\">"))
        XCTAssertTrue(out.contains("let x = 1"))
    }

    func testMermaidBlockGetsClass() {
        let md = """
        ```mermaid
        graph TD
        A --> B
        ```
        """
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<pre class=\"mermaid\">"))
        XCTAssertTrue(out.contains("graph TD"))
        XCTAssertFalse(out.contains("language-mermaid"))   // shouldn't get the wrong class
    }

    func testThematicBreak() {
        let md = "Above\n\n---\n\nBelow"
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<hr>"))
    }

    func testUnorderedList() {
        let md = "- one\n- two\n- three"
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<ul>"))
        XCTAssertTrue(out.contains("<li>one</li>"))
        XCTAssertTrue(out.contains("<li>two</li>"))
    }

    func testOrderedList() {
        let md = "1. first\n2. second"
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<ol>"))
        XCTAssertTrue(out.contains("<li>first</li>"))
    }

    func testTaskListWithCheckbox() {
        let md = "- [ ] todo\n- [x] done"
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<input type=\"checkbox\" disabled>todo"))
        XCTAssertTrue(out.contains("<input type=\"checkbox\" disabled checked>done"))
    }

    func testTable() {
        let md = """
        | A | B |
        |---|---|
        | 1 | 2 |
        | 3 | 4 |
        """
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<table>"))
        XCTAssertTrue(out.contains("<th>A</th>"))
        XCTAssertTrue(out.contains("<th>B</th>"))
        XCTAssertTrue(out.contains("<td>1</td>"))
        XCTAssertTrue(out.contains("<td>4</td>"))
    }

    // MARK: - Images

    func testImage() {
        let md = "![Cat photo](cat.png)"
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<img src=\"cat.png\""))
        XCTAssertTrue(out.contains("alt=\"Cat photo\""))
    }

    // MARK: - Frontmatter behaviour

    func testFrontmatterContentIsStrippedFromBody() {
        let md = """
        ---
        title: Doc
        date: 2026-04-01
        ---

        # Header

        Paragraph.
        """
        let out = MarkdownToHTML.render(md)
        // The frontmatter values should NOT appear in the body.
        XCTAssertFalse(out.contains("date:"))
        XCTAssertFalse(out.contains("2026-04-01"))
        // But the rest should.
        XCTAssertTrue(out.contains("<h1>Header</h1>"))
        XCTAssertTrue(out.contains("<p>Paragraph.</p>"))
    }

    // MARK: - Standalone document shape

    func testStandaloneDocumentHasDoctypeAndBody() {
        let md = "# Hello"
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<!DOCTYPE html>"))
        XCTAssertTrue(out.contains("<html"))
        XCTAssertTrue(out.contains("<body>"))
        XCTAssertTrue(out.contains("</html>"))
        // KaTeX + Mermaid bootstrappers should be present.
        XCTAssertTrue(out.contains("katex"))
        XCTAssertTrue(out.contains("mermaid"))
    }

    // MARK: - Footnotes

    func testFootnoteRefBecomesSuperscriptLink() {
        let md = """
        See [^1] for context.

        [^1]: Important context.
        """
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("<sup class=\"footnote-ref\""))
        XCTAssertTrue(out.contains("id=\"fnref-1\""))
        XCTAssertTrue(out.contains("href=\"#fn-1\""))
        // Definition text shows up in the footer block, not in the body.
        XCTAssertTrue(out.contains("Important context."))
    }

    func testFootnoteDefinitionStrippedFromBody() {
        let md = """
        Body [^1] text.

        [^1]: This is a footnote.

        Next paragraph.
        """
        let out = MarkdownToHTML.render(md)
        // The literal "[^1]: This is a footnote." line shouldn't appear
        // anywhere — neither as text nor inside a paragraph.
        XCTAssertFalse(out.contains("[^1]:"))
        // But the definition body must be in the footnotes section.
        XCTAssertTrue(out.contains("section class=\"footnotes\""))
        XCTAssertTrue(out.contains("This is a footnote."))
        // And the next paragraph still renders.
        XCTAssertTrue(out.contains("<p>Next paragraph.</p>"))
    }

    func testFootnotesNumberedInRefOrder() {
        let md = """
        First [^a] then [^b] then [^a] again.

        [^a]: Apple.
        [^b]: Banana.
        """
        let out = MarkdownToHTML.render(md)
        // First-encountered ref `a` is #1, second-encountered `b` is #2.
        // Re-references to `a` reuse #1.
        XCTAssertTrue(out.contains("<sup class=\"footnote-ref\" id=\"fnref-a\"><a href=\"#fn-a\">1</a></sup>"))
        XCTAssertTrue(out.contains("<sup class=\"footnote-ref\" id=\"fnref-b\"><a href=\"#fn-b\">2</a></sup>"))
        // The footer lists them in encounter order (a, b).
        let aIndex = out.range(of: "id=\"fn-a\"")?.lowerBound
        let bIndex = out.range(of: "id=\"fn-b\"")?.lowerBound
        XCTAssertNotNil(aIndex)
        XCTAssertNotNil(bIndex)
        XCTAssertLessThan(aIndex!, bIndex!)
    }

    func testFootnoteFooterIncludesBackLink() {
        let md = "Body [^1].\n\n[^1]: def"
        let out = MarkdownToHTML.render(md)
        XCTAssertTrue(out.contains("class=\"footnote-back\""))
        XCTAssertTrue(out.contains("href=\"#fnref-1\""))
    }

    func testFootnoteFooterAbsentIfNoFootnotes() {
        let md = "# Heading\n\nNo footnotes here."
        let out = MarkdownToHTML.render(md)
        XCTAssertFalse(out.contains("section class=\"footnotes\""))
    }

    // MARK: - KaTeX

    func testKaTeXAutoRenderConfiguration() {
        let md = "Pythagorean: $a^2 + b^2 = c^2$"
        let out = MarkdownToHTML.render(md)
        // The math source itself stays in plain text — KaTeX picks it up.
        XCTAssertTrue(out.contains("$a^2 + b^2 = c^2$"))
        // The auto-render delimiters config shipped:
        XCTAssertTrue(out.contains("delimiters"))
        XCTAssertTrue(out.contains("display: true"))
    }
}
