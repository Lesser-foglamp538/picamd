import SwiftUI

/// SwiftUI sidebar showing the document's heading hierarchy. Click on
/// a heading to jump the editor's cursor and scroll position there.
struct OutlineSidebar: View {
    @EnvironmentObject private var themeStore: ThemeStore
    let headings: [DocumentHeading]
    let activeHeadingID: Int?
    let onSelect: (DocumentHeading) -> Void

    var body: some View {
        Group {
            if headings.isEmpty {
                emptyState
            } else {
                List {
                    Section(header: header) {
                        ForEach(headings) { h in
                            row(for: h)
                                .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        // Outline shares the editor's background so the surface looks
        // continuous — no jarring chrome strip on the left.
        .background(Color(themeStore.theme.palette.bg))
    }

    // MARK: - Pieces

    private var header: some View {
        // Same reason as `row(for:)` — `.primary` / `.tertiary` follow the
        // macOS system appearance, but the user's palette is independent.
        let paletteFg = Color(themeStore.theme.palette.fg)
        return HStack {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 11))
                .foregroundStyle(paletteFg.opacity(0.65))
            Text("Outline")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(paletteFg.opacity(0.7))
                .textCase(.uppercase)
            Spacer()
            Text("\(headings.count)")
                .font(.system(size: 10))
                .foregroundStyle(paletteFg.opacity(0.45))
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        let paletteFg = Color(themeStore.theme.palette.fg)
        return VStack(spacing: 8) {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(paletteFg.opacity(0.45))
            Text("No headings yet")
                .font(.system(size: 12))
                .foregroundStyle(paletteFg.opacity(0.65))
            Text("Type # then a space to add one.")
                .font(.system(size: 11))
                .foregroundStyle(paletteFg.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func row(for h: DocumentHeading) -> some View {
        let isActive = h.id == activeHeadingID
        // Using `.primary` here resolves to the macOS *system* appearance
        // (Light Mode → black, Dark Mode → white) — but the user's chosen
        // palette is independent. Pick White palette while macOS is in
        // Dark mode, and `.primary` would give white-on-white. Read the
        // foreground colour from the palette instead so the outline always
        // matches the editor canvas.
        let paletteFg = Color(themeStore.theme.palette.fg)
        Button {
            onSelect(h)
        } label: {
            HStack(spacing: 6) {
                indent(for: h.level)
                Text(h.text)
                    .font(font(for: h.level))
                    .foregroundStyle(isActive ? Color.accentColor : paletteFg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func indent(for level: Int) -> some View {
        Color.clear.frame(width: CGFloat(level - 1) * 12)
    }

    private func font(for level: Int) -> Font {
        switch level {
        case 1: return .system(size: 13, weight: .semibold)
        case 2: return .system(size: 12, weight: .medium)
        default: return .system(size: 11, weight: .regular)
        }
    }
}
