import AppKit

/// Lightweight stand-in for a WebView-backed block (Math / Mermaid)
/// that is currently off-screen. Drawn with a single label and the
/// block's first line as a hint, so users see *something* while
/// scrolling at speed instead of empty rectangles.
///
/// The overlay manager swaps these for the real `MathBlockView` /
/// `MermaidBlockView` when the block enters the active viewport
/// window, and back to placeholders when it leaves — keeping the
/// number of live WKWebView processes bounded.
final class PlaceholderBlockView: BlockAttachmentView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")

    override func setupContent() {
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        applyColors()

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.alignment = .left
        addSubview(titleLabel)

        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.alignment = .left
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.maximumNumberOfLines = 2
        addSubview(previewLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            previewLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            previewLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            previewLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            previewLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
        ])

        titleLabel.stringValue = title(for: block.kind).uppercased()
        previewLabel.stringValue = preview(for: block)
    }

    override func desiredHeight(for width: CGFloat) -> CGFloat {
        // Mirror the kind's default height so swapping placeholder ↔
        // real view doesn't cause a layout jump.
        switch block.kind {
        case .table: return EditorBlockDefaults.table
        case .image: return EditorBlockDefaults.image
        case .mathBlock: return EditorBlockDefaults.mathBlock
        case .mermaid: return EditorBlockDefaults.mermaid
        }
    }

    override func appearanceChanged() {
        applyColors()
    }

    private func applyColors() {
        if isDark {
            layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
            layer?.borderColor = NSColor(white: 0.22, alpha: 1).cgColor
        } else {
            layer?.backgroundColor = NSColor(white: 0.97, alpha: 1).cgColor
            layer?.borderColor = NSColor(white: 0.88, alpha: 1).cgColor
        }
    }

    private func title(for kind: BlockKind) -> String {
        switch kind {
        case .mathBlock: return "Math"
        case .mermaid:   return "Mermaid diagram"
        case .table:     return "Table"
        case .image:     return "Image"
        }
    }

    private func preview(for block: ExtractedBlock) -> String {
        let firstNonEmpty = block.payload
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? "—"
        if firstNonEmpty.count > 64 {
            return String(firstNonEmpty.prefix(64)) + "…"
        }
        return firstNonEmpty
    }
}
