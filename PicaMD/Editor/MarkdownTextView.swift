import SwiftUI
import AppKit

/// Token signalling the editor to scroll/jump to a particular range.
/// We use a UUID so consecutive jumps to the same range still trigger.
struct EditorJumpToken: Equatable {
    let id = UUID()
    let location: Int
    let length: Int
    var range: NSRange { NSRange(location: location, length: length) }

    init(_ range: NSRange) {
        self.location = range.location
        self.length = range.length
    }

    static func == (lhs: EditorJumpToken, rhs: EditorJumpToken) -> Bool {
        lhs.id == rhs.id
    }
}

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var jumpToken: EditorJumpToken?
    /// Optional outbound binding: the editor reports the current
    /// caret location whenever the selection changes. The outline
    /// sidebar uses this to auto-highlight the heading the user is
    /// currently editing.
    var cursorLocation: Binding<Int>? = nil
    var theme: EditorTheme = .default
    /// When `true`, every paragraph except the one containing the
    /// caret is rendered with `0.3` foreground alpha — a "spotlight"
    /// reading aid. Toggled via the Focus Mode menu / `⌃⌘F`.
    var focusMode: Bool = false
    /// When `true`, every cursor-position change scrolls the
    /// `NSScrollView` so the caret line lands at the vertical centre
    /// of the viewport. Toggled via the Typewriter Mode menu / `⌃⌘Y`.
    var typewriterMode: Bool = false

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = PicaMDTextView.makeScrollable()

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: EditorLayout.textContainerInsetWidth,
                                             height: EditorLayout.textContainerInsetHeight)
        textView.isAutomaticDataDetectionEnabled = false
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .textColor
        // ⌘F shows a find-bar with built-in Regex toggle; ⌘E uses
        // selection as the search pattern; ⌘G goes to the next match.
        textView.usesFindBar = true
        textView.usesFindPanel = false  // legacy panel is replaced by the bar

        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.isDark = textView.effectiveAppearance.isDark
        context.coordinator.highlighter.theme = theme
        applyTheme(theme, to: scrollView, textView: textView)

        // Wire up the block overlay manager
        let blockManager = BlockOverlayManager()
        blockManager.textView = textView
        blockManager.heightChangeHandler = { [weak coordinator = context.coordinator] in
            coordinator?.scheduleHighlight(delay: 0)
        }
        context.coordinator.blockManager = blockManager

        // Listen for live scroll changes so overlays follow the viewport.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.frameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
        textView.postsFrameChangedNotifications = true

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.documentWillWrite(_:)),
            name: .picaMDDocumentWillWrite,
            object: nil
        )

        context.coordinator.applyHighlightingNow()
        context.coordinator.startObservingAppearance()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let total = (text as NSString).length
            let location = min(selection.location, total)
            let length = min(selection.length, total - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
            context.coordinator.applyHighlightingNow()
        }

        let isDark = scrollView.effectiveAppearance.isDark
        if context.coordinator.isDark != isDark {
            context.coordinator.isDark = isDark
            context.coordinator.applyHighlightingNow()
        }

        // Live theme update
        if context.coordinator.highlighter.theme != theme {
            context.coordinator.highlighter.theme = theme
            applyTheme(theme, to: scrollView, textView: textView)
            context.coordinator.invalidateFullHighlight()
            context.coordinator.applyHighlightingNow()
        }

        // Live mode-flag updates (Focus / Typewriter). Cheap to re-apply
        // even when unchanged because the highlighter short-circuits the
        // dim pass when `focusMode == false`. Typewriter just reads the
        // flag from the coordinator each time the selection moves.
        if context.coordinator.focusMode != focusMode {
            context.coordinator.focusMode = focusMode
            context.coordinator.invalidateFullHighlight()
            context.coordinator.applyHighlightingNow()
        }
        if context.coordinator.typewriterMode != typewriterMode {
            context.coordinator.typewriterMode = typewriterMode
            if typewriterMode {
                context.coordinator.scrollCaretToVerticalCenter()
            }
        }

        // Honour an outside-triggered jump (e.g. from the outline sidebar).
        if let token = jumpToken, token != context.coordinator.lastConsumedJumpToken {
            context.coordinator.lastConsumedJumpToken = token
            applyJump(to: token.range, in: textView)
            // Reset binding so subsequent jumps to the same range still trigger.
            DispatchQueue.main.async {
                self.jumpToken = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Apply background colours, insertion-point colour, and base font
    /// derived from the theme. Called once on creation and on every
    /// theme change.
    private func applyTheme(_ theme: EditorTheme, to scrollView: NSScrollView, textView: NSTextView) {
        let bg = theme.palette.bg
        scrollView.backgroundColor = bg
        textView.backgroundColor = bg
        textView.insertionPointColor = theme.palette.fg
        textView.textColor = theme.palette.fg
        textView.font = theme.bodyFont.font(size: theme.fontBaseSize)
    }

    private func applyJump(to range: NSRange, in textView: NSTextView) {
        let total = (textView.string as NSString).length
        guard total > 0 else { return }
        let safeLoc = max(0, min(range.location, total))
        let safeRange = NSRange(location: safeLoc, length: 0)
        textView.scrollRangeToVisible(safeRange)
        textView.setSelectedRange(safeRange)
        textView.window?.makeFirstResponder(textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        let highlighter = SyntaxHighlighter()
        var blockManager: BlockOverlayManager?
        let fileWatcher = FileWatcher()
        var isDark: Bool = false
        var lastConsumedJumpToken: EditorJumpToken?
        /// Mirror of the parent view's mode flags. Stored on the
        /// coordinator so `textViewDidChangeSelection` (which runs on
        /// every cursor move) can read them without going through the
        /// SwiftUI binding.
        var focusMode: Bool = false
        var typewriterMode: Bool = false
        private var debounceTask: Task<Void, Never>?
        /// Debounce for scroll-driven re-evaluation of the lazy-render
        /// live set. Fast scroll fires `boundsDidChangeNotification` ~60
        /// times/second; we only need to recompute which math/mermaid
        /// blocks should be live-rendered after the user stops moving.
        private var liveSetRefreshTask: Task<Void, Never>?
        private var appearanceObservation: NSKeyValueObservation?
        private var lastDocumentURL: URL?
        private var pendingReloadAlert: Bool = false
        // Initial highlight pass is viewport-only too — saves 400+ ms
        // on a 10k-line cold-open. The textView's own textColor /
        // backgroundColor / font already covers off-viewport chars
        // with the right baseline; only headings/inline markup need
        // the highlighter's styling, and only the visible ones do.
        private var needsFullHighlight: Bool = false

        init(parent: MarkdownTextView) {
            self.parent = parent
            super.init()
            fileWatcher.onExternalChange = { [weak self] event in
                self?.handleExternalFileChange(event)
            }
        }

        deinit {
            appearanceObservation?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }

        // MARK: - External-file-change handling

        private func handleExternalFileChange(_ event: FileWatcher.Event) {
            guard let textView = textView, let window = textView.window else { return }
            guard !pendingReloadAlert else { return }
            pendingReloadAlert = true

            switch event {
            case .modified:
                let alert = NSAlert()
                alert.messageText = "File changed on disk"
                alert.informativeText = "The file was modified by another program. Reload from disk and discard your unsaved changes?"
                alert.addButton(withTitle: "Reload")
                alert.addButton(withTitle: "Keep mine")
                alert.alertStyle = .warning
                alert.beginSheetModal(for: window) { [weak self] response in
                    self?.pendingReloadAlert = false
                    guard let self = self,
                          response == .alertFirstButtonReturn,
                          let url = self.lastDocumentURL,
                          let new = try? String(contentsOf: url, encoding: .utf8) else { return }
                    self.applyExternalReload(text: new)
                    // Re-attach the vnode watcher to the (possibly
                    // newly-created) inode at this path. Without this,
                    // an atomic save by another editor swaps the file
                    // out from under our open file descriptor and we
                    // stop seeing further changes.
                    self.fileWatcher.startWatching(url)
                }
            case .renamedOrDeleted:
                let alert = NSAlert()
                alert.messageText = "File renamed or deleted"
                alert.informativeText = "The file is no longer at its original location. Your edits remain in this window — save again to write them back to a new path."
                alert.addButton(withTitle: "OK")
                alert.alertStyle = .warning
                alert.beginSheetModal(for: window) { [weak self] _ in
                    self?.pendingReloadAlert = false
                    // Re-attach in case the path now points at a fresh
                    // inode again (e.g. someone created a replacement).
                    if let self = self, let url = self.lastDocumentURL {
                        self.fileWatcher.startWatching(url)
                    }
                }
            }
        }

        private func applyExternalReload(text: String) {
            guard let textView = textView else { return }
            // Replace storage atomically; the SwiftUI binding update will
            // also fire via textDidChange.
            let selection = textView.selectedRange()
            textView.string = text
            parent.text = text
            let total = (text as NSString).length
            let location = min(selection.location, total)
            let length = min(selection.length, total - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
            invalidateFullHighlight()
            applyHighlightingNow()
        }

        @objc func scrollDidChange(_ note: Notification) {
            // Cheap: just slide the existing overlay frames to follow the
            // glyph rects. Runs every tick during scroll.
            blockManager?.reposition()

            // Expensive: re-evaluate which math/mermaid blocks should be
            // live-rendered (real WKWebView) vs placeholder. Debounce so
            // we only do it once after the user stops moving — otherwise
            // fast-scroll thrashes WKWebView spawn/teardown.
            liveSetRefreshTask?.cancel()
            liveSetRefreshTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(EditorTiming.lazyLiveSetDebounceMs))
                if Task.isCancelled { return }
                self?.blockManager?.refreshLiveSet()
            }
        }

        @objc func frameDidChange(_ note: Notification) {
            scheduleHighlight(delay: EditorTiming.frameChangeHighlightDebounceMs)
        }

        /// Posted by `MarkdownDocument.fileWrapper(_:)` which runs on a
        /// background queue during save. We must hop to the main actor
        /// before touching any of this @MainActor-isolated coordinator's
        /// state — otherwise Swift's strict-concurrency runtime check
        /// trips and the app crashes with `_dispatch_assert_queue_fail`.
        @objc nonisolated func documentWillWrite(_ note: Notification) {
            // The notification is broadcast app-wide. Filter it by
            // matching the payload's text against THIS coordinator's
            // current buffer so a save in window A doesn't mute the
            // file-watcher of window B (which would let an external
            // edit to B sneak past the reload alert and get silently
            // overwritten on B's next save — F2 in the adversarial
            // review).
            let writtenText = note.userInfo?[MarkdownDocument.willWriteTextKey] as? String
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let writtenText, let current = self.textView?.string,
                   writtenText != current {
                    return  // not our save
                }
                self.fileWatcher.noteSelfWrite()
            }
        }

        func startObservingAppearance() {
            guard let textView = textView else { return }
            appearanceObservation = textView.observe(\.effectiveAppearance, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    let nowDark = view.effectiveAppearance.isDark
                    if self.isDark != nowDark {
                        self.isDark = nowDark
                        self.invalidateFullHighlight()
                        self.applyHighlightingNow()
                    }
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            scheduleHighlight(delay: EditorTiming.highlightDebounceMs)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // Re-render concealment based on the new cursor position.
            // Slightly faster debounce so the user sees the markup expand
            // immediately when stepping into a span.
            scheduleHighlight(delay: EditorTiming.cursorMoveHighlightDebounceMs)
            // Push cursor location upstream (outline auto-highlight).
            if let textView = textView, let binding = parent.cursorLocation {
                let loc = textView.selectedRange().location
                if binding.wrappedValue != loc {
                    binding.wrappedValue = loc
                }
            }
            // Typewriter mode: keep the caret line at viewport mid-height.
            if typewriterMode {
                scrollCaretToVerticalCenter()
            }
        }

        /// Scroll so the caret-glyph rect lands at the vertical centre
        /// of the scroll view's viewport. Called from
        /// `textViewDidChangeSelection` whenever Typewriter Mode is on,
        /// and once when the user toggles Typewriter Mode on so the
        /// initial caret position immediately re-centres.
        func scrollCaretToVerticalCenter() {
            guard let textView = textView,
                  let scrollView = scrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            let cursor = textView.selectedRange()
            // Cursor index can land on a zero-width glyph at end of line —
            // probe a 1-char range so we get a visible bounding rect.
            let probeRange = NSRange(location: cursor.location,
                                      length: cursor.length > 0 ? cursor.length : 1)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: probeRange,
                                                       actualCharacterRange: nil)
            let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange,
                                                       in: textContainer)
            let inset = textView.textContainerInset
            let lineMidY = bounding.minY + inset.height + bounding.height / 2

            let viewportHeight = scrollView.contentView.bounds.height
            // Target: line centre should align with viewport centre.
            let targetY = max(0, lineMidY - viewportHeight / 2)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func scheduleHighlight(delay: Int = 50) {
            debounceTask?.cancel()
            debounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                self?.applyHighlightingNow()
            }
        }

        func applyHighlightingNow() {
            guard let textView = textView, let storage = textView.textStorage else { return }
            let cursor = textView.selectedRange()

            // Pick up the document's file URL for relative-path resolution
            // (used by ImageBlockView) and start watching for external edits.
            // Update on every pass since the window's representedURL may
            // not be set when makeNSView runs.
            if let url = textView.window?.representedURL, url != lastDocumentURL {
                lastDocumentURL = url
                blockManager?.documentURL = url
                fileWatcher.startWatching(url)
                if let qmdView = textView as? PicaMDTextView {
                    qmdView.documentURL = url
                }
                // Push frontmatter title + tags + body preview to
                // Spotlight so PicaMD-known files show up with smart
                // metadata instead of the generic plain-text snippet.
                SpotlightIndexer.index(url: url, source: textView.string)
                // Tell the MCP-sidecar (`picamd-mcp`) the user has
                // this document open. It shows up in the sidecar's
                // `workspace.openDocuments` tool result so Claude Code
                // can read/search/edit it through MCP.
                ActiveDocumentsRegistry.shared.register(url: url)
            }

            let source = textView.string
            let blocks = BlockExtractor.extract(from: source)
            let availableWidth = max(120, textView.bounds.width
                                     - textView.textContainerInset.width * 2 - 16)
            let heights = blockManager?.desiredHeights(for: blocks, width: availableWidth) ?? [:]

            // Incremental highlight: only re-attribute the visible viewport
            // (plus a generous buffer) on edits/cursor-moves. Off-screen
            // attributes keep their last state, which is correct because
            // the buffer covers any markup that crosses the viewport edge.
            // First pass per session is full-doc so every char gets a base
            // font + foreground colour.
            let viewport = needsFullHighlight ? nil : computeViewportCharRange()
            needsFullHighlight = false

            highlighter.highlight(
                textStorage: storage,
                isDark: isDark,
                cursorRange: cursor,
                blocks: blocks,
                blockHeights: heights,
                viewportRange: viewport,
                focusMode: focusMode
            )
            blockManager?.update(blocks: blocks, cursorActiveRanges: [cursor])

            // Refresh footnote-tooltip index so hover-popovers stay in
            // sync with the source. Cheap (regex pass over the doc).
            if let qmdView = textView as? PicaMDTextView {
                qmdView.footnoteTooltip.updateIndex(from: source)
            }
        }

        /// Forces the next `applyHighlightingNow()` call to re-highlight
        /// the entire document instead of only the visible viewport.
        /// Use after destructive changes (theme switch, dark-mode flip,
        /// large reload from disk).
        func invalidateFullHighlight() {
            needsFullHighlight = true
        }

        private func computeViewportCharRange() -> NSRange? {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return nil
            }
            let visibleRect = textView.visibleRect
            // Empty visible rect means the view hasn't laid out yet -
            // fall back to full doc.
            guard visibleRect.height > 0 else { return nil }
            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let total = textView.textStorage?.length ?? 0
            // Buffer covers any inline-markup or block boundary that
            // crosses the viewport edge in real-world docs.
            let buffer = EditorBuffer.viewportContext
            let start = max(0, charRange.location - buffer)
            let end = min(total, charRange.location + charRange.length + buffer)
            return NSRange(location: start, length: end - start)
        }
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
