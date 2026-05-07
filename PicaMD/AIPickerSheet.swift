import AppKit
import SwiftUI

/// Modal-on-top fuzzy picker for AI presets, summoned by `⌃Space`.
/// Reuses the same fuzzy-match scoring as the Command Palette so
/// behaviour is consistent — you type, the list narrows, ↑/↓ to move,
/// Return to fire, Escape to cancel.
///
/// Why a fresh sheet rather than re-using `CommandPalette`? Because
/// the picker's row ALSO needs to show the preset's hotkey
/// assignment (`⌃⌘3`), and on selection we get back an `AIPreset`,
/// not a generic action closure. The `CommandPalette` shape would
/// have grown an awkward sum-type to fit both. Two small files is
/// cleaner than one bigger one with a flag.
@MainActor
enum AIPickerSheet {

    /// Show the picker as a window-modal sheet on `host`'s window
    /// (typically the editor's). On dismissal-with-pick, call
    /// `onPick` once with the chosen preset; on cancel, call
    /// nothing. The sheet self-cleans up either way.
    static func present(over host: NSView,
                          presets: [AIPreset],
                          onPick: @escaping (AIPreset) -> Void) {
        guard let parentWindow = host.window else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true

        let palette = ThemeStore.currentPalette
        let view = AIPickerView(
            presets: presets,
            palette: palette,
            onPick: { picked in
                parentWindow.endSheet(panel)
                onPick(picked)
            },
            onCancel: {
                parentWindow.endSheet(panel)
            }
        )
        let host = NSHostingController(rootView: view)
        panel.contentView = host.view

        parentWindow.beginSheet(panel, completionHandler: nil)
    }
}

// MARK: - SwiftUI view

private struct AIPickerView: View {
    let presets: [AIPreset]
    let palette: Palette
    let onPick: (AIPreset) -> Void
    let onCancel: () -> Void

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var searchFocused: Bool

    private var filtered: [(preset: AIPreset, score: Int)] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return presets.map { ($0, 0) }
        }
        return presets
            .compactMap { p -> (AIPreset, Int)? in
                guard let score = FuzzyMatch.score(query: query, in: p.name) else {
                    return nil
                }
                return (p, score)
            }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
                .background(Color(palette.fg).opacity(0.08))
            results
        }
        .background(Color(palette.bg))
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                searchFocused = true
            }
        }
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .onKeyPress(.escape) { onCancel(); return .handled }
        .onKeyPress(.return) { performSelected(); return .handled }
        .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color(palette.accent))
            TextField("Run AI preset… (Return to fire, Esc to cancel)",
                       text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .foregroundStyle(Color(palette.fg))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var results: some View {
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
                        ForEach(Array(items.enumerated()), id: \.element.preset.id) { idx, pair in
                            row(preset: pair.preset, isSelected: idx == selectedIndex)
                                .id(pair.preset.id)
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
                    scrollProxy.scrollTo(items[new].preset.id, anchor: .center)
                }
            }
        }
    }

    private func row(preset: AIPreset, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12))
                .foregroundStyle(
                    isSelected
                        ? Color(palette.accent)
                        : Color(palette.fg).opacity(0.55)
                )
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Color(palette.fg))
                Text(preset.insertionMode.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(palette.fg).opacity(0.5))
            }
            Spacer()
            if let key = preset.hotkey {
                Text("⌃⌘\(key)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(palette.fg).opacity(0.55))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(palette.fg).opacity(0.08))
                    )
            }
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

    private func moveSelection(by delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func performSelected() {
        let items = filtered
        guard items.indices.contains(selectedIndex) else {
            onCancel()
            return
        }
        onPick(items[selectedIndex].preset)
    }
}
