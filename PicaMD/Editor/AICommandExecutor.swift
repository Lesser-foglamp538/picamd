import AppKit

/// Runs an `AIPreset` against the user's current selection in an
/// `NSTextView` and applies the response according to the preset's
/// `insertionMode`. Pulled out of `PicaMDTextView` so the logic
/// (selection-extraction, prompt-resolution, insertion) is testable
/// without a live view.
@MainActor
struct AICommandExecutor {

    enum FailureReason: LocalizedError {
        case aiDisabled
        case noTextView
        case invalidEndpoint
        case providerError(Error)

        var errorDescription: String? {
            switch self {
            case .aiDisabled:           return "AI is off — enable it in Settings → AI"
            case .noTextView:           return "No active editor"
            case .invalidEndpoint:      return "AI endpoint URL is invalid — check Settings → AI"
            case .providerError(let e): return e.localizedDescription
            }
        }
    }

    /// Read the current selection (or the cursor's paragraph if no
    /// selection), build the prompt, send it to the configured
    /// provider, and apply the response according to `preset.insertionMode`.
    ///
    /// Long-running: the network call is awaited inside the function.
    /// Caller should provide visual feedback (cursor dim, spinner)
    /// before invoking.
    static func run(preset: AIPreset, in textView: NSTextView) async throws {
        let config = AIConfig.load()
        guard config.enabled else { throw FailureReason.aiDisabled }

        let provider = preset.providerOverride ?? config.defaultProvider
        let model = preset.modelOverride ?? config.model(for: provider)
        let endpoint = config.endpoint(for: provider)
        let apiKey = Keychain.get(account: provider.keychainAccount)

        guard let client = AIClient(
            provider: provider,
            endpointString: endpoint,
            model: model,
            apiKey: apiKey
        ) else {
            throw FailureReason.invalidEndpoint
        }

        guard let storage = textView.textStorage else { throw FailureReason.noTextView }
        let source = storage.string
        let selection = textView.selectedRange()
        let context = SelectionContext.derive(from: source, range: selection)

        let prompt = preset.resolvePrompt(selection: context.text)
        let response: String
        do {
            response = try await client.complete(
                userPrompt: prompt,
                systemPrompt: preset.systemPrompt
            )
        } catch {
            throw FailureReason.providerError(error)
        }

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        applyResponse(trimmed, preset: preset, context: context, in: textView)
    }

    // MARK: - Selection extraction

    struct SelectionContext {
        /// The text the user prompt was derived from. Either the
        /// explicit selection, or the cursor's paragraph if none.
        var text: String
        /// Range to use as the "anchor" for insertion. Equals the
        /// selection when there was one, otherwise the paragraph
        /// range so "append below" puts the response after the
        /// paragraph.
        var anchorRange: NSRange
        /// `true` if the user explicitly selected something. When
        /// `false`, replace-modes downgrade to append-modes
        /// automatically (we never wipe an unselected paragraph).
        var hasExplicitSelection: Bool

        static func derive(from source: String, range: NSRange) -> SelectionContext {
            let nsSource = source as NSString
            if range.length > 0 {
                return SelectionContext(
                    text: nsSource.substring(with: range),
                    anchorRange: range,
                    hasExplicitSelection: true
                )
            }
            // Empty selection → use the paragraph the cursor sits in.
            let paragraph = nsSource.paragraphRange(for: range)
            return SelectionContext(
                text: nsSource.substring(with: paragraph),
                anchorRange: paragraph,
                hasExplicitSelection: false
            )
        }
    }

    // MARK: - Insertion

    /// Apply `response` to `textView` according to `preset.insertionMode`.
    /// Goes through `shouldChangeText`/`didChangeText` so undo + the
    /// highlighter pick the change up properly.
    private static func applyResponse(
        _ response: String,
        preset: AIPreset,
        context: SelectionContext,
        in textView: NSTextView
    ) {
        // Resolve effective insertion mode. If the user invoked a
        // replace-mode preset without an explicit selection, downgrade
        // to "appendBelow" — we won't risk wiping a whole paragraph
        // they didn't intentionally highlight.
        let mode: AIPreset.InsertionMode
        if preset.insertionMode == .replaceSelection && !context.hasExplicitSelection {
            mode = .appendBelow
        } else {
            mode = preset.insertionMode
        }

        switch mode {
        case .replaceSelection:
            replace(in: textView, range: context.anchorRange, with: response)
        case .appendBelow:
            let insertion = "\n\n" + response + "\n"
            let target = NSRange(location: NSMaxRange(context.anchorRange), length: 0)
            replace(in: textView, range: target, with: insertion)
        case .asBlockquote:
            let quoted = response
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> " + $0 }
                .joined(separator: "\n")
            let insertion = "\n\n" + quoted + "\n"
            let target = NSRange(location: NSMaxRange(context.anchorRange), length: 0)
            replace(in: textView, range: target, with: insertion)
        case .asHTMLComment:
            let escaped = response
                .replacingOccurrences(of: "-->", with: "-- >")
            let insertion = "\n\n<!--\n\(escaped)\n-->\n"
            let target = NSRange(location: NSMaxRange(context.anchorRange), length: 0)
            replace(in: textView, range: target, with: insertion)
        case .showInPopover:
            showResponsePopover(response, near: textView, anchor: context.anchorRange)
        }
    }

    private static func replace(in textView: NSTextView, range: NSRange, with text: String) {
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        let nsText = text as NSString
        let newCursor = NSRange(location: range.location + nsText.length, length: 0)
        textView.setSelectedRange(newCursor)
    }

    /// Floating popover for the "Show in popover" insertion mode —
    /// lets the user read the response without committing to inserting
    /// it. Anchored to the bounding rect of the selection (or
    /// paragraph) so it appears next to the relevant text.
    private static func showResponsePopover(
        _ text: String,
        near textView: NSTextView,
        anchor: NSRange
    ) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: anchor,
                                                    actualCharacterRange: nil)
        let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange,
                                                    in: textContainer)
        let inset = textView.textContainerInset
        let positioningRect = NSRect(
            x: bounding.midX + inset.width,
            y: bounding.maxY + inset.height,
            width: 1,
            height: 1
        )

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 200)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let label = NSTextView()
        label.isEditable = false
        label.isSelectable = true
        label.string = text
        label.font = .systemFont(ofSize: 13)
        label.textContainerInset = NSSize(width: 12, height: 12)
        label.drawsBackground = false
        scroll.documentView = label
        scroll.frame = NSRect(x: 0, y: 0, width: 360, height: 200)

        let host = NSViewController()
        host.view = scroll
        popover.contentViewController = host
        popover.show(relativeTo: positioningRect, of: textView, preferredEdge: .maxY)
    }
}
