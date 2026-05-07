import Foundation

/// One of the built-in editor "looks". Picking a preset sets *typography
/// + structure* defaults (body/heading font, scale, code style, etc.)
/// but leaves palette and accent untouched — the user can freely combine
/// "Editorial preset + OLED palette + pink accent".
enum PresetVariant: String, CaseIterable, Identifiable, Codable {
    /// The current refined-as-is PicaMD look. Mono body, calm palette.
    case stockPlus = "stock-plus"

    /// New York serif H1 with a hairline rule, sans body. For long-form
    /// essays and prose-heavy notes.
    case editorial = "editorial"

    /// SF Pro headings, SF Mono body, tinted code blocks. The native
    /// macOS Tahoe look — calm, system-default-feeling.
    case tahoe = "tahoe"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stockPlus: return "Stock+"
        case .editorial: return "Editorial"
        case .tahoe:     return "Tahoe"
        }
    }

    var subtitle: String {
        switch self {
        case .stockPlus: return "Refined as-is. Mono body, calm palette."
        case .editorial: return "Serif H1 with hairline rule. Sans body."
        case .tahoe:     return "SF Pro headings, SF Mono body, tinted code."
        }
    }

    /// Apply this preset's typography/structure defaults to `theme`.
    /// Palette and accent are preserved so the user keeps their colour
    /// choices when switching presets.
    func applyDefaults(to theme: inout EditorTheme) {
        theme.preset = self
        switch self {
        case .stockPlus:
            theme.bodyFont      = .mono
            theme.headingFont   = .sans
            theme.headingScale  = .defaultScale
            theme.headingRule   = false
            theme.codeStyle     = .card
            theme.showStatusBar = true

        case .editorial:
            theme.bodyFont      = .sans
            theme.headingFont   = .serif
            theme.headingScale  = .airy
            theme.headingRule   = true
            theme.codeStyle     = .card
            theme.showStatusBar = true

        case .tahoe:
            theme.bodyFont      = .mono
            theme.headingFont   = .sans
            theme.headingScale  = .defaultScale
            theme.headingRule   = false
            theme.codeStyle     = .tinted
            theme.showStatusBar = true
        }
    }
}
