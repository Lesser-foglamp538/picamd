import AppKit

/// Manages the lifecycle of block-attachment overlay views inside an
/// NSTextView. The text storage retains the original markdown source
/// (concealed via clear-color + tiny font + extra line height), and
/// these overlay views are rendered on top at the corresponding glyph
/// positions, so the markdown looks "rendered" while staying editable.
///
/// Math and Mermaid blocks live behind a viewport-aware lazy layer:
/// only blocks within an expanded viewport window get their real
/// `WebViewBlockView` (which spawns a WKWebView process). Off-screen
/// blocks render as a cheap `PlaceholderBlockView` instead. This
/// keeps RAM bounded at large docs with many math/mermaid blocks.
@MainActor
final class BlockOverlayManager {
    weak var textView: NSTextView?
    var documentURL: URL?

    /// View currently presenting each block. Could be a real renderer
    /// (Table/Image/Math/Mermaid) or a `PlaceholderBlockView`.
    private var views: [ExtractedBlock: BlockAttachmentView] = [:]
    /// Last reported live-rendered height per block.
    private var blockHeights: [ExtractedBlock: CGFloat] = [:]
    private var lastBlocks: [ExtractedBlock] = []
    /// Cache of the last-known cursor-active ranges so `refreshLiveSet()`
    /// can re-evaluate the viewport without losing the cursor-overlay-
    /// hiding behaviour.
    private var lastCursorActiveRanges: [NSRange] = []

    /// How far above and below the visible glyph rect we keep blocks
    /// "live". Two viewport heights of pre/post-scroll buffer feels
    /// generous without exploding RAM.
    private let viewportLiveBufferMultiplier: CGFloat = 2.0
    /// Hard ceiling on the number of WebView-backed blocks that may
    /// be live at once, regardless of viewport size. Single-WKWebView
    /// process is ~10 MB resident; this caps us at ~120 MB worst-case
    /// for math/mermaid alone.
    private let maxLiveWebViews: Int = 12

    // MARK: - Public API

    /// Compute desired heights for every block, so the highlighter can
    /// reserve enough vertical space (via min-line-height) before the
    /// overlay views are positioned on top.
    func desiredHeights(for blocks: [ExtractedBlock], width: CGFloat) -> [ExtractedBlock: CGFloat] {
        guard width > 0 else { return [:] }
        var out: [ExtractedBlock: CGFloat] = [:]
        for block in blocks {
            switch block.kind {
            case .table, .image:
                // Synchronous-measurable. Use the existing view if any,
                // otherwise spin up a fresh measuring instance (cheap
                // for tables/images compared to webviews).
                if let v = views[block], !(v is PlaceholderBlockView) {
                    v.frame.size.width = width
                    out[block] = v.desiredHeight(for: width)
                } else {
                    let probe = makeRealView(for: block)
                    probe.frame.size.width = width
                    out[block] = probe.desiredHeight(for: width)
                }
            case .mathBlock, .mermaid:
                // Webview height is reported async; reserve last-known
                // or a sensible default until the JS callback updates us.
                out[block] = blockHeights[block] ?? defaultHeight(for: block.kind)
            }
        }
        return out
    }

    /// Sync overlay views with the current set of blocks. Adds/removes
    /// views as needed and repositions all of them.
    func update(blocks: [ExtractedBlock], cursorActiveRanges: [NSRange]) {
        guard let textView = textView else { return }

        // Remove views for blocks that disappeared
        let blockSet = Set(blocks)
        for (key, view) in views where !blockSet.contains(key) {
            view.removeFromSuperview()
            views.removeValue(forKey: key)
            blockHeights.removeValue(forKey: key)
        }

        // Decide which webview-backed blocks should be live this pass.
        let liveSet = computeLiveSet(among: blocks)

        // Create / promote / demote views as needed.
        for block in blocks {
            let needsLive = liveSet.contains(block)
            let existing = views[block]
            let isPlaceholder = existing is PlaceholderBlockView
            let isRealKind: Bool
            switch block.kind {
            case .table, .image: isRealKind = true   // always real
            case .mathBlock, .mermaid: isRealKind = needsLive
            }
            let needsRecreation = existing == nil
                || (isRealKind && isPlaceholder)
                || (!isRealKind && existing != nil && !isPlaceholder)
            if needsRecreation {
                existing?.removeFromSuperview()
                let v: BlockAttachmentView
                if isRealKind {
                    v = makeRealView(for: block)
                } else {
                    v = PlaceholderBlockView(block: block, documentURL: documentURL)
                }
                v.autoresizingMask = []
                views[block] = v
                textView.addSubview(v)
            }
        }

        // Hide views whose range overlaps a cursor-active range
        for (block, view) in views {
            let active = cursorActiveRanges.contains { intersects($0, block.range) }
            view.isHidden = active
        }

        lastBlocks = blocks
        lastCursorActiveRanges = cursorActiveRanges
        reposition()
    }

    /// Re-run the live-set computation against the *current* viewport
    /// without re-extracting blocks. Cheap to call on scroll — promotes
    /// blocks that just entered the viewport buffer from
    /// `PlaceholderBlockView` to a real `WebViewBlockView`, and demotes
    /// blocks that just left. Caller should debounce (~150 ms idle) so
    /// fast-scroll doesn't thrash WKWebView spawn/teardown.
    func refreshLiveSet() {
        guard !lastBlocks.isEmpty else { return }
        update(blocks: lastBlocks, cursorActiveRanges: lastCursorActiveRanges)
    }

    /// Position all overlay views to match their text ranges.
    func reposition() {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let storageLength = textView.textStorage?.length ?? 0
        for (block, view) in views {
            let r = block.range
            guard r.location + r.length <= storageLength else {
                view.isHidden = true
                continue
            }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            guard glyphRange.length > 0 else {
                view.isHidden = true
                continue
            }
            let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let inset = textView.textContainerInset
            let frame = NSRect(
                x: bounding.minX + inset.width,
                y: bounding.minY + inset.height + 2,
                width: max(EditorLayout.blockOverlayMinWidth, bounding.width - 4),
                height: max(40, bounding.height - 6)
            )
            view.frame = frame
        }
    }

    /// Forget all overlays (e.g. when the document changes drastically).
    func clear() {
        for (_, view) in views {
            view.removeFromSuperview()
        }
        views.removeAll()
        blockHeights.removeAll()
    }

    // MARK: - Live-set computation

    /// Pick the webview-backed blocks that should be rendered as real
    /// (vs. as `PlaceholderBlockView`) on this pass. Tables and images
    /// are always real — they're cheap. Math/mermaid get the lazy
    /// treatment.
    private func computeLiveSet(among blocks: [ExtractedBlock]) -> Set<ExtractedBlock> {
        var result = Set<ExtractedBlock>()

        let webViewKinds: Set<BlockKind> = [.mathBlock, .mermaid]
        let webBlocks = blocks.filter { webViewKinds.contains($0.kind) }
        guard let viewport = currentViewportCharRange() else {
            // Layout not ready: keep first N as live, rest as placeholders.
            for b in webBlocks.prefix(maxLiveWebViews) { result.insert(b) }
            return result
        }

        // Score each web-block by distance to the viewport (0 = fully inside).
        struct Scored { let block: ExtractedBlock; let distance: Int }
        let viewportEnd = viewport.location + viewport.length
        let scored: [Scored] = webBlocks.map { b in
            let start = b.range.location
            let end = b.range.location + b.range.length
            let distance: Int
            if end < viewport.location {
                distance = viewport.location - end
            } else if start > viewportEnd {
                distance = start - viewportEnd
            } else {
                distance = 0
            }
            return Scored(block: b, distance: distance)
        }
        // Sort by distance, take top N.
        let sorted = scored.sorted { $0.distance < $1.distance }
        for s in sorted.prefix(maxLiveWebViews) {
            result.insert(s.block)
        }
        return result
    }

    private func currentViewportCharRange() -> NSRange? {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }
        let visible = textView.visibleRect
        guard visible.height > 0 else { return nil }
        // Expand by buffer factor so blocks just off-screen also stay live.
        let expanded = visible.insetBy(dx: 0,
                                        dy: -visible.height * viewportLiveBufferMultiplier)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: expanded,
                                                    in: textContainer)
        return layoutManager.characterRange(forGlyphRange: glyphRange,
                                              actualGlyphRange: nil)
    }

    // MARK: - Real-view factory

    private func makeRealView(for block: ExtractedBlock) -> BlockAttachmentView {
        let view: BlockAttachmentView
        switch block.kind {
        case .table:
            view = TableBlockView(block: block, documentURL: documentURL)
        case .image:
            view = ImageBlockView(block: block, documentURL: documentURL)
        case .mathBlock:
            let v = MathBlockView(block: block, documentURL: documentURL)
            v.onHeightChange = { [weak self] newHeight in
                self?.blockHeights[block] = newHeight
                self?.notifyHeightChange()
            }
            view = v
        case .mermaid:
            let v = MermaidBlockView(block: block, documentURL: documentURL)
            v.onHeightChange = { [weak self] newHeight in
                self?.blockHeights[block] = newHeight
                self?.notifyHeightChange()
            }
            view = v
        }
        view.autoresizingMask = []
        return view
    }

    private func defaultHeight(for kind: BlockKind) -> CGFloat {
        switch kind {
        case .table: return EditorBlockDefaults.table
        case .image: return EditorBlockDefaults.image
        case .mathBlock: return EditorBlockDefaults.mathBlock
        case .mermaid: return EditorBlockDefaults.mermaid
        }
    }

    private func intersects(_ a: NSRange, _ b: NSRange) -> Bool {
        let aEnd = a.location + a.length
        let bEnd = b.location + b.length
        return a.location <= bEnd && b.location <= aEnd
    }

    /// Called when an async-loading block (math/mermaid) reports a new
    /// height after rendering. We need to ask the highlighter to reserve
    /// more line-height so the overlay isn't clipped.
    var heightChangeHandler: (() -> Void)?

    private func notifyHeightChange() {
        heightChangeHandler?()
    }
}
