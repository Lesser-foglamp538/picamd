import Foundation

/// Single source of truth for the regex patterns shared between the
/// `BlockExtractor` (which finds overlay blocks for the BlockOverlayManager)
/// and the `SyntaxHighlighter` (which paints inline attributes and the
/// concealment fence-lines around the same blocks).
///
/// Keeping these in one place removes the previous drift risk where
/// `BlockExtractor.mathBlockRegex` and
/// `SyntaxHighlighter.mathBlockRegex` were two compiled instances of
/// the same pattern that could (and did) get edited independently.
enum MarkdownRegexes {
    static let mathBlock = compile(#"(?m)^\$\$[\s\S]*?^\$\$\s*$"#)
    static let mermaidFence = compile(#"(?m)^```mermaid[ \t]*\n[\s\S]*?^```[ \t]*$"#)
    static let fencedCode = compile(#"(?m)^([`~]{3,})[^\n]*\n[\s\S]*?^\1[ \t]*$"#)
    /// Block-level image: a line that is *only* an `![alt](url)` (with
    /// optional Pandoc-style `{width=N}` attribute set).
    static let blockImage = compile(
        #"^[ \t]*!\[([^\]]*)\]\(([^)]+)\)(\{[^}]*\})?[ \t]*$"#,
        options: [.anchorsMatchLines]
    )
    /// Inline image: same pattern without the line anchors. Multiple
    /// matches per line are possible.
    static let inlineImage = compile(#"!\[([^\]]*)\]\(([^)]+)\)"#)
    /// Pandoc-style `{width=N}` attribute parsed out of an image line.
    static let imageResizeAttribute = compile(
        #"\bwidth\s*=\s*(\d+)"#,
        options: [.caseInsensitive]
    )

    private static func compile(_ pattern: String,
                                 options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }
}
