import AppKit

/// Native overlay view for a parsed pipe-table block. Draws header
/// background, alternating body rows, vertical column separators, and
/// inline-bold/italic/code in cells. No webview involved.
final class TableBlockView: BlockAttachmentView {
    private let rowHeight: CGFloat = 26
    private let cellHPadding: CGFloat = 12
    private let headerColor = NSColor.labelColor

    override func setupContent() {
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        applyColors()
    }

    private func applyColors() {
        if isDark {
            layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
            layer?.borderColor = NSColor(white: 0.25, alpha: 1).cgColor
        } else {
            layer?.backgroundColor = NSColor(white: 0.99, alpha: 1).cgColor
            layer?.borderColor = NSColor(white: 0.85, alpha: 1).cgColor
        }
    }

    override func appearanceChanged() {
        applyColors()
        needsDisplay = true
    }

    override func desiredHeight(for width: CGFloat) -> CGFloat {
        guard let parsed = block.parseTable() else { return rowHeight }
        let total = (1 + parsed.rows.count) * Int(rowHeight) + 8
        return CGFloat(total)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let parsed = block.parseTable() else { return }
        let columnCount = max(parsed.headers.count, parsed.rows.first?.count ?? 0)
        guard columnCount > 0 else { return }

        let columnWidth = bounds.width / CGFloat(columnCount)
        let dark = isDark

        // Header background
        let headerRect = NSRect(x: 0, y: bounds.height - rowHeight, width: bounds.width, height: rowHeight)
        (dark ? NSColor(white: 0.20, alpha: 1) : NSColor(white: 0.94, alpha: 1)).setFill()
        headerRect.fill()

        // Body row alternating
        for (i, _) in parsed.rows.enumerated() {
            if i % 2 == 1 {
                let y = bounds.height - rowHeight - CGFloat(i + 1) * rowHeight
                let row = NSRect(x: 0, y: y, width: bounds.width, height: rowHeight)
                (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.97, alpha: 1)).setFill()
                row.fill()
            }
        }

        // Vertical column separators
        let sepColor = dark ? NSColor(white: 0.25, alpha: 1) : NSColor(white: 0.88, alpha: 1)
        sepColor.setStroke()
        for c in 1..<columnCount {
            let x = CGFloat(c) * columnWidth
            let p = NSBezierPath()
            p.move(to: NSPoint(x: x, y: 0))
            p.line(to: NSPoint(x: x, y: bounds.height))
            p.lineWidth = 0.5
            p.stroke()
        }

        // Horizontal: under header
        let underHeaderY = bounds.height - rowHeight
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 0, y: underHeaderY))
        p.line(to: NSPoint(x: bounds.width, y: underHeaderY))
        p.lineWidth = 0.5
        p.stroke()

        let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 13, weight: .regular)
        let textColor = dark ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.10, alpha: 1)

        // Headers
        for (col, text) in parsed.headers.enumerated() {
            let x = CGFloat(col) * columnWidth + cellHPadding
            let cellWidth = columnWidth - 2 * cellHPadding
            let cellRect = NSRect(x: x, y: underHeaderY, width: cellWidth, height: rowHeight)
            drawText(parseInline(text),
                     in: cellRect,
                     font: headerFont,
                     color: textColor,
                     alignment: alignmentFor(parsed.alignments, col: col))
        }

        // Rows
        for (rowIdx, row) in parsed.rows.enumerated() {
            let y = bounds.height - rowHeight - CGFloat(rowIdx + 1) * rowHeight
            for (col, text) in row.enumerated() {
                let x = CGFloat(col) * columnWidth + cellHPadding
                let cellWidth = columnWidth - 2 * cellHPadding
                let cellRect = NSRect(x: x, y: y, width: cellWidth, height: rowHeight)
                drawText(parseInline(text),
                         in: cellRect,
                         font: bodyFont,
                         color: textColor,
                         alignment: alignmentFor(parsed.alignments, col: col))
            }
        }
    }

    private func alignmentFor(_ aligns: [TableAlignment?], col: Int) -> NSTextAlignment {
        guard col < aligns.count, let a = aligns[col] else { return .left }
        switch a {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    private func drawText(_ attrString: NSAttributedString,
                          in rect: NSRect,
                          font: NSFont,
                          color: NSColor,
                          alignment: NSTextAlignment) {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        para.lineBreakMode = .byTruncatingTail

        let mutable = NSMutableAttributedString(attributedString: attrString)
        mutable.addAttributes([
            .paragraphStyle: para,
            .foregroundColor: color,
        ], range: NSRange(location: 0, length: mutable.length))
        mutable.enumerateAttribute(.font, in: NSRange(location: 0, length: mutable.length), options: []) { val, r, _ in
            if val == nil {
                mutable.addAttribute(.font, value: font, range: r)
            } else if let f = val as? NSFont {
                let traited = NSFontManager.shared.convert(f, toSize: font.pointSize)
                mutable.addAttribute(.font, value: traited, range: r)
            }
        }

        let textHeight = mutable.size().height
        let drawRect = NSRect(
            x: rect.minX,
            y: rect.minY + (rect.height - textHeight) / 2,
            width: rect.width,
            height: textHeight
        )
        mutable.draw(in: drawRect)
    }

    // Static patterns reused for every cell render — one compile per
    // process, not per cell render pass.
    private static let cellBoldRegex = try! NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#)
    private static let cellItalicRegex = try! NSRegularExpression(pattern: #"(?<!\*)\*([^*]+)\*(?!\*)"#)
    private static let cellCodeRegex = try! NSRegularExpression(pattern: #"`([^`]+)`"#)

    /// Lightweight inline parser — handles **bold**, *italic*, `code`. Enough
    /// to make `**bold**` render as bold inside table cells.
    private func parseInline(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        let nsString = text as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        // Bold
        for m in Self.cellBoldRegex.matches(in: text, range: fullRange).reversed() {
            let inner = nsString.substring(with: m.range(at: 1))
            let attr = NSAttributedString(
                string: inner,
                attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
            )
            result.replaceCharacters(in: m.range, with: attr)
        }
        // Italic (only single-asterisk pairs not already eaten by bold above)
        let updated = result.string as NSString
        let updatedRange = NSRange(location: 0, length: updated.length)
        for m in Self.cellItalicRegex.matches(in: result.string, range: updatedRange).reversed() {
            let inner = updated.substring(with: m.range(at: 1))
            let italicFont = NSFontManager.shared.font(
                withFamily: NSFont.systemFont(ofSize: 13).familyName ?? "Helvetica",
                traits: [.italicFontMask],
                weight: 5,
                size: 13
            ) ?? NSFont.systemFont(ofSize: 13)
            let attr = NSAttributedString(string: inner, attributes: [.font: italicFont])
            result.replaceCharacters(in: m.range, with: attr)
        }
        // Inline code
        let afterItalic = result.string as NSString
        let r = NSRange(location: 0, length: afterItalic.length)
        for m in Self.cellCodeRegex.matches(in: result.string, range: r).reversed() {
            let inner = afterItalic.substring(with: m.range(at: 1))
            let attr = NSAttributedString(
                string: inner,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .backgroundColor: NSColor(white: 0.5, alpha: 0.15),
                ]
            )
            result.replaceCharacters(in: m.range, with: attr)
        }
        return result
    }
}
