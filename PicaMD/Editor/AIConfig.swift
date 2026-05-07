import Foundation

/// User-facing AI configuration. Two pieces of state live here:
///
///   1. `defaultProvider` + per-provider endpoint/model overrides —
///      the "what server am I talking to" config.
///   2. `enabled` — master kill switch. When `false`, the editor's
///      ⌃⌘1…⌃⌘9 hotkeys and ⌃Space picker no-op out.
///
/// API keys live in `Keychain` (not in here). The default endpoint
/// + model strings live in the `AIProvider` enum.
///
/// All fields default to safe values: AI is **off**, no key set,
/// endpoint pointed at localhost. Opt-in only.
struct AIConfig: Equatable, Codable {
    var enabled: Bool
    var defaultProvider: AIProvider

    /// Per-provider settings, indexed by `AIProvider.rawValue`. Keeps
    /// each provider's state independent — switching from OpenAI to
    /// Anthropic doesn't lose your OpenAI endpoint customisation.
    var providers: [String: ProviderSettings]

    struct ProviderSettings: Equatable, Codable {
        var endpointURL: String
        var model: String
    }

    static let `default` = AIConfig(
        enabled: false,
        defaultProvider: .anthropic,
        providers: [
            AIProvider.anthropic.rawValue: ProviderSettings(
                endpointURL: AIProvider.anthropic.defaultEndpoint,
                model: AIProvider.anthropic.defaultModel
            ),
            AIProvider.openai.rawValue: ProviderSettings(
                endpointURL: AIProvider.openai.defaultEndpoint,
                model: AIProvider.openai.defaultModel
            ),
            AIProvider.localOpenAICompat.rawValue: ProviderSettings(
                endpointURL: AIProvider.localOpenAICompat.defaultEndpoint,
                model: AIProvider.localOpenAICompat.defaultModel
            ),
        ]
    )

    /// Convenience getters/setters for a provider's fields. Falls back
    /// to defaults if the dictionary entry is missing (defensive — should
    /// never happen with `default` above, but the field is `var` so a
    /// stored config might in theory drift).

    func endpoint(for provider: AIProvider) -> String {
        providers[provider.rawValue]?.endpointURL ?? provider.defaultEndpoint
    }

    func model(for provider: AIProvider) -> String {
        providers[provider.rawValue]?.model ?? provider.defaultModel
    }

    mutating func setEndpoint(_ url: String, for provider: AIProvider) {
        var s = providers[provider.rawValue]
            ?? ProviderSettings(endpointURL: provider.defaultEndpoint,
                                 model: provider.defaultModel)
        s.endpointURL = url
        providers[provider.rawValue] = s
    }

    mutating func setModel(_ model: String, for provider: AIProvider) {
        var s = providers[provider.rawValue]
            ?? ProviderSettings(endpointURL: provider.defaultEndpoint,
                                 model: provider.defaultModel)
        s.model = model
        providers[provider.rawValue] = s
    }

    // MARK: - Persistence

    private static let key = "PicaMD.ai.config.v2"

    /// Migrate the old-style v1 keys (set by the original LM-Studio-only
    /// AI hook) into the new shape. Runs at most once per defaults
    /// instance because `load(...)` only reaches the migration path
    /// when no `v2` blob exists yet.
    private static func migrateV1(defaults: UserDefaults) -> AIConfig? {
        let oldEnabledKey = "PicaMD.ai.enabled"
        let oldEndpointKey = "PicaMD.ai.endpointURL"
        let oldModelKey = "PicaMD.ai.model"
        let hasOldData = defaults.object(forKey: oldEnabledKey) != nil
                      || defaults.string(forKey: oldEndpointKey) != nil
        guard hasOldData else { return nil }

        var cfg = AIConfig.default
        cfg.enabled = defaults.bool(forKey: oldEnabledKey)
        cfg.defaultProvider = .localOpenAICompat
        if let url = defaults.string(forKey: oldEndpointKey), !url.isEmpty {
            cfg.setEndpoint(url, for: .localOpenAICompat)
        }
        if let m = defaults.string(forKey: oldModelKey), !m.isEmpty {
            cfg.setModel(m, for: .localOpenAICompat)
        }
        return cfg
    }

    static func load(defaults: UserDefaults = .standard) -> AIConfig {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AIConfig.self, from: data) {
            return decoded
        }
        if let migrated = migrateV1(defaults: defaults) {
            migrated.save(to: defaults)
            return migrated
        }
        return .default
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
