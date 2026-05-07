import SwiftUI

/// macOS-native settings sheet. Lives behind ⌘,. Sections mirror the
/// Tweaks panel from the Claude design package.
struct SettingsView: View {
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        TabView {
            PresetTab().tabItem {
                Label("Presets", systemImage: "rectangle.3.group")
            }
            PaletteTab().tabItem {
                Label("Palette", systemImage: "circle.lefthalf.filled")
            }
            TypographyTab().tabItem {
                Label("Typography", systemImage: "textformat")
            }
            BlocksTab().tabItem {
                Label("Blocks", systemImage: "square.grid.2x2")
            }
            AITab().tabItem {
                Label("AI", systemImage: "sparkles")
            }
        }
        .frame(minWidth: 460, minHeight: 380)
        .padding(20)
    }
}

// MARK: - AI (Providers + Presets)
//
// Single flat scrollable tab. Earlier iterations used a nested
// `TabView` (collapsed ambiguously into the outer strip with two
// "Presets" tabs side-by-side) and a segmented Picker (rendered
// as zero-height inside the parent Form layout). One scrollable
// view with two sections turns out to be the cleanest fit:
//   - Providers section at top
//   - Presets section below
// Both editable in place; preset edit / new-preset still happens
// in a sheet.

private struct AITab: View {
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                AIProviderTab()
                Divider()
                    .padding(.horizontal, 4)
                AIPresetsTab()
            }
            .padding(.vertical, 8)
        }
    }
}

private struct AIProviderTab: View {
    @State private var config: AIConfig = AIConfig.load()
    @State private var apiKeys: [String: String] = [:]

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI assistance", isOn: $config.enabled)
                    .onChange(of: config.enabled) { _, _ in config.save() }
            } footer: {
                Text("Off by default. **⌃Space** opens the preset picker; **⌃⌘1**…**⌃⌘9** invoke presets directly. API keys are stored in the macOS keychain (never in plaintext).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            Section("Default provider") {
                Picker("Provider", selection: $config.defaultProvider) {
                    ForEach(AIProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .onChange(of: config.defaultProvider) { _, _ in config.save() }
                .disabled(!config.enabled)
            }

            ForEach(AIProvider.allCases) { provider in
                Section(provider.displayName) {
                    let endpointBinding = Binding<String>(
                        get: { config.endpoint(for: provider) },
                        set: { newValue in
                            config.setEndpoint(newValue, for: provider)
                            config.save()
                        }
                    )
                    let modelBinding = Binding<String>(
                        get: { config.model(for: provider) },
                        set: { newValue in
                            config.setModel(newValue, for: provider)
                            config.save()
                        }
                    )

                    TextField("Endpoint URL", text: endpointBinding,
                               prompt: Text(provider.defaultEndpoint))
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .disabled(!config.enabled)
                    TextField("Model", text: modelBinding,
                               prompt: Text(provider.defaultModel))
                        .textFieldStyle(.roundedBorder)
                        .disabled(!config.enabled)

                    if provider.requiresAPIKey {
                        SecureField(
                            "API key",
                            text: Binding<String>(
                                get: { apiKeys[provider.rawValue] ?? "" },
                                set: { apiKeys[provider.rawValue] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .disabled(!config.enabled)
                        .onSubmit { saveAPIKey(for: provider) }

                        HStack {
                            if Keychain.get(account: provider.keychainAccount) != nil {
                                Label("Key stored in Keychain",
                                       systemImage: "checkmark.shield.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Button("Save key") { saveAPIKey(for: provider) }
                                .disabled(!config.enabled)
                            Button("Remove") {
                                Keychain.delete(account: provider.keychainAccount)
                                apiKeys[provider.rawValue] = ""
                            }
                            .disabled(!config.enabled)
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func saveAPIKey(for provider: AIProvider) {
        let value = (apiKeys[provider.rawValue] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        Keychain.set(value: value, account: provider.keychainAccount)
        // Clear the field after save so the secret doesn't sit in
        // memory longer than necessary.
        apiKeys[provider.rawValue] = ""
    }
}

private struct AIPresetsTab: View {
    @StateObject private var store = PicaMDTextView.presetStore
    @State private var editingPreset: AIPreset? = nil
    @State private var showingNewSheet: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            list
            Divider()
            footer
        }
        .padding(.top, 8)
        .sheet(item: $editingPreset) { preset in
            AIPresetEditor(preset: preset) { updated in
                store.update(updated)
                editingPreset = nil
            } onCancel: {
                editingPreset = nil
            }
        }
        .sheet(isPresented: $showingNewSheet) {
            AIPresetEditor(
                preset: AIPreset(
                    id: UUID(),
                    name: "New preset",
                    systemPrompt: nil,
                    userPromptTemplate: "{{selection}}",
                    insertionMode: .appendBelow,
                    hotkey: nil
                )
            ) { newPreset in
                store.add(newPreset)
                showingNewSheet = false
            } onCancel: {
                showingNewSheet = false
            }
        }
    }

    private var list: some View {
        List {
            ForEach(store.presets) { preset in
                Button {
                    editingPreset = preset
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(preset.insertionMode.displayName)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let key = preset.hotkey {
                            Text("⌃⌘\(key)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in store.remove(at: offsets) }
            .onMove { source, dest in store.move(from: source, to: dest) }
        }
        .frame(minHeight: 220)
    }

    private var footer: some View {
        HStack {
            Button("Add preset") { showingNewSheet = true }
            Spacer()
            Button("Reset to built-ins") { store.resetToDefaults() }
                .help("Replace all presets with the 9 built-in starter presets.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct AIPresetEditor: View {
    @State var preset: AIPreset
    let onSave: (AIPreset) -> Void
    let onCancel: () -> Void

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $preset.name)
                Picker("Hotkey", selection: hotkeyBinding) {
                    Text("None").tag(0)
                    ForEach(1...9, id: \.self) { d in
                        Text("⌃⌘\(d)").tag(d)
                    }
                }
            }
            Section("Prompt") {
                TextField(
                    "System prompt (optional)",
                    text: Binding(
                        get: { preset.systemPrompt ?? "" },
                        set: { preset.systemPrompt = $0.isEmpty ? nil : $0 }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...6)

                TextField(
                    "User prompt template (use {{selection}})",
                    text: $preset.userPromptTemplate,
                    axis: .vertical
                )
                .lineLimit(3...10)
            }
            Section("Insertion") {
                Picker("Mode", selection: $preset.insertionMode) {
                    ForEach(AIPreset.InsertionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { onCancel() }
                    Button("Save") { onSave(preset) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 480, height: 480)
    }

    private var hotkeyBinding: Binding<Int> {
        Binding(
            get: { preset.hotkey ?? 0 },
            set: { preset.hotkey = $0 == 0 ? nil : $0 }
        )
    }
}

// MARK: - Preset

private struct PresetTab: View {
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preset")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(PresetVariant.allCases) { preset in
                presetCard(preset)
            }

            Spacer()
            HStack {
                Spacer()
                Button("Reset to Default") {
                    themeStore.resetToDefault()
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func presetCard(_ preset: PresetVariant) -> some View {
        let isActive = themeStore.theme.preset == preset
        Button {
            themeStore.selectPreset(preset)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
                    Text(String(preset.displayName.prefix(1)))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isActive ? Color.accentColor : .secondary)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(preset.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isActive ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Palette

private struct PaletteTab: View {
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Palette")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                ForEach(PaletteName.allCases) { name in
                    paletteSwatch(name)
                }
            }

            Divider()

            Text("Accent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                ForEach(AccentChoice.allCases) { accent in
                    accentSwatch(accent)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func paletteSwatch(_ name: PaletteName) -> some View {
        let isActive = themeStore.theme.paletteName == name
        Button {
            themeStore.setPalette(name)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(name.palette.bg))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isActive ? Color.accentColor : Color.gray.opacity(0.2),
                                lineWidth: isActive ? 2 : 1)
                    VStack(spacing: 2) {
                        Capsule()
                            .fill(Color(name.palette.fg))
                            .frame(width: 28, height: 3)
                        Capsule()
                            .fill(Color(name.palette.fgMuted))
                            .frame(width: 22, height: 3)
                    }
                }
                .frame(width: 70, height: 50)
                Text(name.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func accentSwatch(_ accent: AccentChoice) -> some View {
        let isActive = themeStore.theme.accent == accent
        Button {
            themeStore.setAccent(accent)
        } label: {
            ZStack {
                Circle()
                    .fill(Color(accent.color))
                if isActive {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 18, height: 18)
                    Circle()
                        .stroke(Color(accent.color), lineWidth: 2)
                        .frame(width: 24, height: 24)
                }
            }
            .frame(width: 24, height: 24)
            .help(accent.displayName)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Typography

private struct TypographyTab: View {
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        Form {
            Section {
                Picker("Body Font", selection: Binding(
                    get: { themeStore.theme.bodyFont },
                    set: { themeStore.setBodyFont($0) }
                )) {
                    ForEach(BodyFontFamily.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Heading Font", selection: Binding(
                    get: { themeStore.theme.headingFont },
                    set: { themeStore.setHeadingFont($0) }
                )) {
                    ForEach(HeadingFontFamily.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Heading Scale", selection: Binding(
                    get: { themeStore.theme.headingScale },
                    set: { themeStore.setHeadingScale($0) }
                )) {
                    ForEach(HeadingScale.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Hairline under H1", isOn: Binding(
                    get: { themeStore.theme.headingRule },
                    set: { themeStore.setHeadingRule($0) }
                ))

                HStack {
                    Text("Base font size")
                    Spacer()
                    Text("\(Int(themeStore.theme.fontBaseSize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
                Slider(value: Binding(
                    get: { themeStore.theme.fontBaseSize },
                    set: { themeStore.setBaseFontSize($0) }
                ), in: 12...18, step: 0.5)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Blocks

private struct BlocksTab: View {
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        Form {
            Section {
                Picker("Code blocks", selection: Binding(
                    get: { themeStore.theme.codeStyle },
                    set: { themeStore.setCodeStyle($0) }
                )) {
                    ForEach(CodeBlockStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                Toggle("Show status bar", isOn: Binding(
                    get: { themeStore.theme.showStatusBar },
                    set: { themeStore.setShowStatusBar($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
        .environmentObject(ThemeStore())
}
