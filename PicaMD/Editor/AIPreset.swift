import Foundation

/// One user-invokable AI command. Combines a prompt template, an
/// insertion mode, and (optionally) a keyboard shortcut.
///
/// The prompt template uses `{{selection}}` as the placeholder for
/// the user's current selection or paragraph. We chose this instead
/// of plain `%@` so the templates are also human-readable in Settings.
struct AIPreset: Codable, Equatable, Identifiable {

    /// Stable UUID — used both as `id` and as the preset's row key in
    /// `AIPresetStore`. Generated on creation, never reassigned.
    var id: UUID
    var name: String
    var systemPrompt: String?
    var userPromptTemplate: String
    var insertionMode: InsertionMode

    /// 1…9 = `⌃⌘<digit>` shortcut, `nil` = preset is invocable only
    /// through the `⌃Space` fuzzy picker. We deliberately limit to
    /// single-digit shortcuts to keep the keyboard surface predictable.
    var hotkey: Int?

    /// Optional per-preset provider/model override. When `nil` the
    /// preset uses whatever's set as the default in `AIConfig`.
    var providerOverride: AIProvider?
    var modelOverride: String?

    enum InsertionMode: String, Codable, CaseIterable, Identifiable {
        case replaceSelection
        case appendBelow
        case asBlockquote
        case asHTMLComment
        case showInPopover

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .replaceSelection:  return "Replace selection"
            case .appendBelow:       return "Append below"
            case .asBlockquote:      return "Insert as blockquote"
            case .asHTMLComment:     return "Insert as HTML comment"
            case .showInPopover:     return "Show in popover (don't insert)"
            }
        }
    }

    /// Render the user-prompt template against a concrete selection.
    /// Returns the substituted prompt with `{{selection}}` replaced.
    /// If the template doesn't contain the placeholder, we APPEND the
    /// selection on a new line — that's friendlier than silently
    /// dropping the user's text when they edited a template wrong.
    func resolvePrompt(selection: String) -> String {
        let placeholder = "{{selection}}"
        if userPromptTemplate.contains(placeholder) {
            return userPromptTemplate.replacingOccurrences(of: placeholder, with: selection)
        }
        return userPromptTemplate + "\n\n" + selection
    }
}

// MARK: - Default starter presets

extension AIPreset {
    /// 9 built-in presets the user can immediately try after enabling
    /// AI. Their hotkeys are pre-bound to ⌃⌘1…⌃⌘9.
    ///
    /// They're written so each one has a `<= 200`-token output ceiling
    /// for snappy UX, and so each is genuinely useful for the *same*
    /// kind of writing tasks the user said they care about: drafts,
    /// project notes, README-style docs.
    static let defaults: [AIPreset] = [
        AIPreset(
            id: UUID(),
            name: "Bereinige Markdown",
            systemPrompt: "You're a careful Markdown editor. Clean up the user's text into well-formed Markdown without changing meaning. Replace fancy quotes with straight quotes, em-dashes (—) with comma or parentheses where appropriate, normalise whitespace, fix obvious typos. Output ONLY the cleaned Markdown, no preamble.",
            userPromptTemplate: "{{selection}}",
            insertionMode: .replaceSelection,
            hotkey: 1
        ),
        AIPreset(
            id: UUID(),
            name: "Fasse zusammen",
            systemPrompt: "You're a concise summarizer. Produce a crisp 3–5 bullet summary of the user's text. Keep the user's language (German stays German). Output ONLY the bullet list, no preamble.",
            userPromptTemplate: "{{selection}}",
            insertionMode: .asBlockquote,
            hotkey: 2
        ),
        AIPreset(
            id: UUID(),
            name: "Schreibe natürlicher",
            systemPrompt: "Rewrite the user's text in natural, flowing prose. Keep the same language. Same tone, same level of formality. Don't add new information. Output ONLY the rewritten text.",
            userPromptTemplate: "{{selection}}",
            insertionMode: .replaceSelection,
            hotkey: 3
        ),
        AIPreset(
            id: UUID(),
            name: "Erweitere diesen Absatz",
            systemPrompt: "Continue the user's paragraph naturally — same tone, same direction. Add 2–4 sentences of substance. Same language. Don't repeat what's already said. Output ONLY the new continuation, starting from where the user left off.",
            userPromptTemplate: "{{selection}}",
            insertionMode: .appendBelow,
            hotkey: 4
        ),
        AIPreset(
            id: UUID(),
            name: "Fix Grammatik & Rechtschreibung",
            systemPrompt: "Fix grammar, punctuation, and spelling in the user's text. Don't change meaning, voice, or vocabulary unless required for correctness. Same language. Output ONLY the corrected text.",
            userPromptTemplate: "{{selection}}",
            insertionMode: .replaceSelection,
            hotkey: 5
        ),
        AIPreset(
            id: UUID(),
            name: "Übersetze (DE ↔ EN)",
            systemPrompt: "Translate the user's text. If it's German, translate to English. If it's English, translate to German. If it's a mix, default to whichever is dominant. Preserve Markdown formatting. Output ONLY the translation.",
            userPromptTemplate: "{{selection}}",
            insertionMode: .appendBelow,
            hotkey: 6
        ),
        AIPreset(
            id: UUID(),
            name: "Mache formeller",
            systemPrompt: "Rewrite the user's text in a more formal register — appropriate for a business letter or technical documentation. Same language. Same factual content. Output ONLY the rewritten text.",
            userPromptTemplate: "{{selection}}",
            insertionMode: .replaceSelection,
            hotkey: 7
        ),
        AIPreset(
            id: UUID(),
            name: "Mache lockerer",
            systemPrompt: "Rewrite the user's text in a more casual, conversational register. Same language. Same factual content. Output ONLY the rewritten text.",
            userPromptTemplate: "{{selection}}",
            insertionMode: .replaceSelection,
            hotkey: 8
        ),
        AIPreset(
            id: UUID(),
            name: "Custom prompt",
            systemPrompt: nil,
            userPromptTemplate: "{{selection}}",
            insertionMode: .appendBelow,
            hotkey: 9
        ),
    ]
}
