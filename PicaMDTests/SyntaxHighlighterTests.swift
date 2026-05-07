import XCTest
import AppKit
@testable import PicaMD

@MainActor
final class SyntaxHighlighterTests: XCTestCase {

    private func makeStorage(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        // Set a baseline font so attribute comparisons are well-defined.
        let base = NSFont.systemFont(ofSize: 15)
        storage.addAttributes([.font: base], range: NSRange(location: 0, length: storage.length))
        return storage
    }

    func testHeadingHasLargerFont() {
        let highlighter = SyntaxHighlighter()
        let storage = makeStorage("# Heading\n\nBody text.")
        highlighter.highlight(textStorage: storage, isDark: false, cursorRange: NSRange(location: 100, length: 0))

        // Heading font should be larger than the body font.
        let headingFont = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        let bodyFont = storage.attribute(.font, at: 12, effectiveRange: nil) as? NSFont

        XCTAssertNotNil(headingFont, "Heading should have a font attribute")
        XCTAssertNotNil(bodyFont, "Body should have a font attribute")
        if let h = headingFont, let b = bodyFont {
            XCTAssertGreaterThan(h.pointSize, b.pointSize,
                                 "Heading should be visually larger than body")
        }
    }

    func testHeadingMarkerIsConcealedWhenCursorIsAway() {
        let highlighter = SyntaxHighlighter()
        let source = "# Heading\n\nBody."
        let storage = makeStorage(source)
        // Cursor at end of doc, far from the heading
        let cursor = NSRange(location: source.utf16.count, length: 0)
        highlighter.highlight(textStorage: storage, isDark: false, cursorRange: cursor)

        // The `#` character is at index 0
        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.clear, "Heading marker should be concealed (clear) when cursor is away")
    }

    func testHeadingMarkerVisibleWhenCursorIsNearby() {
        let highlighter = SyntaxHighlighter()
        let source = "# Heading\n\nBody."
        let storage = makeStorage(source)
        // Cursor inside the heading line
        let cursor = NSRange(location: 4, length: 0)
        highlighter.highlight(textStorage: storage, isDark: false, cursorRange: cursor)

        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(color, NSColor.clear,
                          "Heading marker should be visible when cursor is in the same line")
    }

    func testInlineCodeHasMonospaceFont() {
        let highlighter = SyntaxHighlighter()
        let source = "Plain `code` text."
        let storage = makeStorage(source)
        highlighter.highlight(textStorage: storage, isDark: false, cursorRange: NSRange(location: 100, length: 0))

        // Index pointing into the word `code` (between the backticks)
        let codeIndex = (source as NSString).range(of: "code").location
        let font = storage.attribute(.font, at: codeIndex, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(font?.fontName.lowercased().contains("mono") == true ||
                      font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true,
                      "Inline code should use a monospaced font")
    }

    func testBoldHasBoldTrait() {
        let highlighter = SyntaxHighlighter()
        let source = "Plain **strong** text."
        let storage = makeStorage(source)
        highlighter.highlight(textStorage: storage, isDark: false, cursorRange: NSRange(location: 100, length: 0))

        let strongIndex = (source as NSString).range(of: "strong").location
        let font = storage.attribute(.font, at: strongIndex, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true,
                      "Bold span should carry the bold trait")
    }

    func testEmptyDocumentDoesNotCrash() {
        let highlighter = SyntaxHighlighter()
        let storage = NSTextStorage(string: "")
        highlighter.highlight(textStorage: storage, isDark: false, cursorRange: NSRange(location: 0, length: 0))
        // Just reaching here without crashing is the test.
        XCTAssertEqual(storage.length, 0)
    }

    func testHandlesMultiByteCharacters() {
        let highlighter = SyntaxHighlighter()
        // 4-byte codepoints (emoji) used to break NSRange-based logic
        let source = "# 📚 Heading 中文 🇩🇪\n\nBody."
        let storage = makeStorage(source)
        // Should not crash, regardless of cursor position
        highlighter.highlight(textStorage: storage, isDark: false, cursorRange: NSRange(location: 5, length: 0))
        highlighter.highlight(textStorage: storage, isDark: true, cursorRange: NSRange(location: storage.length, length: 0))
        XCTAssertGreaterThan(storage.length, 0)
    }
}
