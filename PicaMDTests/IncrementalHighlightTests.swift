import XCTest
import AppKit
@testable import PicaMD

@MainActor
final class IncrementalHighlightTests: XCTestCase {

    private func makeStorage(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let base = NSFont.systemFont(ofSize: 15)
        storage.addAttributes([.font: base], range: NSRange(location: 0, length: storage.length))
        return storage
    }

    /// Headings outside the viewport must keep their previous attributes
    /// (here: untouched system-font baseline) instead of being re-styled.
    func testOffViewportHeadingIsNotRestyled() {
        let highlighter = SyntaxHighlighter()
        let lines = (0..<200).map { "# Heading \($0)" }
        let source = lines.joined(separator: "\n")
        let storage = makeStorage(source)

        // Apply a baseline that DIFFERS from what the highlighter would
        // produce, so we can detect whether off-viewport ranges were touched.
        let sentinel = NSColor(red: 1, green: 0, blue: 1, alpha: 1)
        storage.addAttribute(.foregroundColor,
                             value: sentinel,
                             range: NSRange(location: 0, length: storage.length))

        // Pretend only the first ~3 lines are visible
        let viewport = NSRange(location: 0, length: 30)
        highlighter.highlight(textStorage: storage,
                              isDark: false,
                              cursorRange: NSRange(location: -1, length: 0),
                              viewportRange: viewport)

        // A heading at the very end (~line 199, ≥ 1500 chars in) must
        // still carry the sentinel colour we set.
        let farIndex = (source as NSString).length - 5
        let farColor = storage.attribute(.foregroundColor, at: farIndex, effectiveRange: nil) as? NSColor
        XCTAssertEqual(farColor, sentinel,
                       "Off-viewport range should not be re-coloured by the highlighter")
    }

    /// In-viewport headings DO get the heading colour applied.
    func testInViewportHeadingIsRestyled() {
        let highlighter = SyntaxHighlighter()
        let source = "# Visible heading\n\nBody"
        let storage = makeStorage(source)

        let viewport = NSRange(location: 0, length: storage.length)
        highlighter.highlight(textStorage: storage,
                              isDark: false,
                              cursorRange: NSRange(location: 100, length: 0),
                              viewportRange: viewport)

        // Look at the actual heading text, e.g. position of "V"
        let idx = (source as NSString).range(of: "Visible").location
        let color = storage.attribute(.foregroundColor, at: idx, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(color)
        XCTAssertNotEqual(color, NSColor(red: 1, green: 0, blue: 1, alpha: 1),
                          "In-viewport text should be re-coloured by the highlighter")
    }

    /// Performance: a 10k-line document should re-highlight a single
    /// viewport (~50 lines) much faster than the full document.
    /// We don't assert hard numbers, just check that incremental is at
    /// least 3× faster than full on a modern Mac.
    func testIncrementalHighlightIsFaster() {
        let highlighter = SyntaxHighlighter()
        let lines = (0..<10_000).map { "## Section \($0) — *italic* and **bold**." }
        let source = lines.joined(separator: "\n")
        let storage = makeStorage(source)

        // Warm-up
        highlighter.highlight(textStorage: storage, isDark: false)

        let fullStart = Date()
        highlighter.highlight(textStorage: storage,
                              isDark: false,
                              cursorRange: NSRange(location: 0, length: 0))
        let fullElapsed = Date().timeIntervalSince(fullStart)

        // Viewport ~ first 50 lines
        let viewport = NSRange(location: 0, length: min(2000, storage.length))
        let incStart = Date()
        highlighter.highlight(textStorage: storage,
                              isDark: false,
                              cursorRange: NSRange(location: 0, length: 0),
                              viewportRange: viewport)
        let incElapsed = Date().timeIntervalSince(incStart)

        print("Full-highlight: \(Int(fullElapsed * 1000)) ms")
        print("Incremental:    \(Int(incElapsed * 1000)) ms")
        XCTAssertLessThan(incElapsed * 3, fullElapsed,
                          "Incremental highlight should be at least 3× faster than full")
    }
}
