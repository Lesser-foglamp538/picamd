import SwiftUI

/// Slim status-strip above the editor that surfaces the parsed YAML
/// frontmatter (title / date / tags) so the user sees the document's
/// metadata at a glance without scrolling to the top of the source.
///
/// Hidden when there's no frontmatter, so a quick `.md` file with just
/// a heading doesn't grow chrome.
struct FrontmatterBar: View {
    @EnvironmentObject private var themeStore: ThemeStore
    let frontmatter: Frontmatter

    var body: some View {
        if shouldShow {
            content
        }
    }

    private var shouldShow: Bool {
        frontmatter.range != nil
            && (frontmatter.title != nil
                || frontmatter.date != nil
                || !frontmatter.tags.isEmpty)
    }

    @ViewBuilder
    private var content: some View {
        let palette = themeStore.theme.palette
        HStack(spacing: 10) {
            if let title = frontmatter.title, !title.isEmpty {
                Image(systemName: "doc.text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(palette.fg).opacity(0.55))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(palette.fg))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if !frontmatter.tags.isEmpty {
                Divider()
                    .frame(height: 12)
                tagChips(for: frontmatter.tags, palette: palette)
            }

            Spacer()

            if let date = frontmatter.date {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(palette.fg).opacity(0.45))
                Text(date)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(palette.fg).opacity(0.6))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Color(palette.bgTint)
                .opacity(0.9)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(palette.fg).opacity(0.08))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func tagChips(for tags: [String], palette: Palette) -> some View {
        // Cap the number of visible chips so a doc with 30 tags doesn't
        // push the title off the bar. Overflow becomes a `+N` chip.
        let visible = Array(tags.prefix(6))
        let overflow = max(0, tags.count - visible.count)
        HStack(spacing: 4) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, tag in
                chip(text: tag, palette: palette)
            }
            if overflow > 0 {
                chip(text: "+\(overflow)", palette: palette, muted: true)
            }
        }
    }

    private func chip(text: String, palette: Palette, muted: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(
                muted
                    ? Color(palette.fg).opacity(0.45)
                    : Color(palette.accent)
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(palette.accent).opacity(muted ? 0.05 : 0.12))
            )
            .lineLimit(1)
    }
}
