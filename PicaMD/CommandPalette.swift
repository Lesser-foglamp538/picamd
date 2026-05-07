import SwiftUI

/// `⌘⇧P` overlay sheet — a fuzzy-matched action picker that aggregates
/// every heading in the current document plus a small set of editor
/// commands (toggle outline, toggle focus mode, toggle typewriter
/// mode). Type to narrow, ↑/↓ to move the selection, Return to
/// execute, Escape to dismiss.
///
/// Items are scored by the fuzzy matcher in `FuzzyMatch.swift` —
/// pure logic, unit-tested separately. The sheet itself is
/// presentation only.

struct CommandPaletteAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let icon: String?
    let perform: () -> Void
}

struct CommandPalette: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @Binding var isPresented: Bool
    let actions: [CommandPaletteAction]

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var searchFocused: Bool

    private var filtered: [(action: CommandPaletteAction, score: Int)] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return actions.map { ($0, 0) }
        }
        return actions
            .compactMap { action -> (CommandPaletteAction, Int)? in
                guard let score = FuzzyMatch.score(query: query, in: action.title) else {
                    return nil
                }
                return (action, score)
            }
            .sorted { $0.1 > $1.1 }   // higher score first
    }

    var body: some View {
        let palette = themeStore.theme.palette
        VStack(spacing: 0) {
            searchField(palette: palette)
            Divider()
                .background(Color(palette.fg).opacity(0.08))
            resultsList(palette: palette)
        }
        .frame(width: 520)
        .frame(maxHeight: 420)
        .background(Color(palette.bg))
        .onAppear {
            // Reset selection + focus the field. Wrapped in a tiny
            // `Task` so AppKit has a tick to move the field into the
            // window before we ask for first-responder.
            query = ""
            selectedIndex = 0
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                searchFocused = true
            }
        }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        // Esc / Return / arrow keys handled here so they don't hit the editor.
        .onKeyPress(.escape) { isPresented = false; return .handled }
        .onKeyPress(.return) {
            performSelected()
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
    }

    // MARK: - Pieces

    private func searchField(palette: Palette) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(palette.fg).opacity(0.5))
            TextField("Type to filter — Return to run, Esc to close",
                       text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .foregroundStyle(Color(palette.fg))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func resultsList(palette: Palette) -> some View {
        let items = filtered
        return ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if items.isEmpty {
                        Text("No matches")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(palette.fg).opacity(0.45))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.action.id) { idx, pair in
                            row(for: pair.action,
                                 isSelected: idx == selectedIndex,
                                 palette: palette)
                                .id(pair.action.id)
                                .onTapGesture {
                                    selectedIndex = idx
                                    performSelected()
                                }
                        }
                    }
                }
            }
            .onChange(of: selectedIndex) { _, new in
                guard new >= 0, new < items.count else { return }
                withAnimation(.linear(duration: 0.05)) {
                    scrollProxy.scrollTo(items[new].action.id, anchor: .center)
                }
            }
        }
    }

    private func row(for action: CommandPaletteAction,
                      isSelected: Bool,
                      palette: Palette) -> some View {
        HStack(spacing: 10) {
            if let icon = action.icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(
                        isSelected
                            ? Color(palette.accent)
                            : Color(palette.fg).opacity(0.6)
                    )
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Color(palette.fg))
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(palette.fg).opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            isSelected
                ? Color(palette.accent).opacity(0.15)
                : Color.clear
        )
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func moveSelection(by delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta).clamped(to: 0...(count - 1))
    }

    private func performSelected() {
        let items = filtered
        guard items.indices.contains(selectedIndex) else {
            isPresented = false
            return
        }
        let action = items[selectedIndex].action
        // Close FIRST so the action runs against a settled UI state
        // (e.g. jumping to a heading doesn't fight the sheet's
        // dismissal animation).
        isPresented = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            action.perform()
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
