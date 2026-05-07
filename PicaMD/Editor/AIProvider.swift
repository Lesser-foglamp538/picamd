import Foundation

/// Which API shape the AI client should speak. PicaMD ships with
/// three first-class providers and a "custom OpenAI-compatible"
/// fallback that covers Groq / Together / OpenRouter / vLLM /
/// llama.cpp's `--api`.
///
/// The provider determines:
///   - the request body shape (Anthropic's `/v1/messages` differs
///     materially from OpenAI's `/v1/chat/completions`),
///   - which auth header to attach (`x-api-key` vs `Authorization`),
///   - and whether an API key is required at all (local servers
///     usually don't need one).
enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case anthropic
    case openai
    case localOpenAICompat   // LM Studio, Ollama, llama.cpp, …

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic:           return "Anthropic (Claude)"
        case .openai:              return "OpenAI (GPT)"
        case .localOpenAICompat:   return "Local (LM Studio / Ollama)"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .anthropic:           return "https://api.anthropic.com/v1"
        case .openai:              return "https://api.openai.com/v1"
        case .localOpenAICompat:   return "http://localhost:1234/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic:           return "claude-sonnet-4-6"
        case .openai:              return "gpt-4o-mini"
        case .localOpenAICompat:   return "local-model"
        }
    }

    /// Whether the user must provide an API key. Local servers
    /// typically don't authenticate, but we still let the user
    /// optionally set one in case they've put their local server
    /// behind a reverse proxy that demands a header.
    var requiresAPIKey: Bool {
        switch self {
        case .anthropic, .openai:  return true
        case .localOpenAICompat:   return false
        }
    }

    /// Stable key for storing the provider's API key in the keychain.
    /// Includes the provider rawValue so a user can have multiple
    /// providers configured concurrently without the keys colliding.
    var keychainAccount: String {
        "PicaMD.ai.\(rawValue).apiKey"
    }
}

// MARK: - Request building

/// One shot of completion across providers. The struct is provider-
/// agnostic; `AIRequestBuilder` turns it into the right HTTP request
/// per provider.
struct AICompletionRequest {
    /// The user's prompt (after preset templating). For Claude /
    /// OpenAI this becomes the only `user` message; system prompt
    /// is carried separately.
    var userPrompt: String
    /// Optional system instruction. For Anthropic this maps to the
    /// top-level `system` field; for OpenAI it becomes the first
    /// `system` message.
    var systemPrompt: String?
    var model: String
    var maxTokens: Int = 2048
}

/// Builds provider-specific `URLRequest`s from an `AICompletionRequest`.
/// Splitting this out from `AIClient` keeps the network glue testable
/// in isolation — the unit tests can verify Anthropic-vs-OpenAI body
/// shapes without spinning up a server.
enum AIRequestBuilder {

    static func build(
        provider: AIProvider,
        endpoint: URL,
        apiKey: String?,
        request: AICompletionRequest
    ) throws -> URLRequest {
        switch provider {
        case .anthropic:
            return try buildAnthropic(endpoint: endpoint, apiKey: apiKey, req: request)
        case .openai, .localOpenAICompat:
            return try buildOpenAI(provider: provider,
                                    endpoint: endpoint,
                                    apiKey: apiKey,
                                    req: request)
        }
    }

    // MARK: Anthropic

    private static func buildAnthropic(
        endpoint: URL, apiKey: String?, req: AICompletionRequest
    ) throws -> URLRequest {
        guard let key = apiKey, !key.isEmpty else {
            throw AIError.invalidResponse("Anthropic requires an API key — set one in Settings → AI")
        }
        var url = endpoint
        // Tolerate the user typing `…/v1` or `…/v1/` — strip a trailing
        // `/messages` if they over-specified.
        if !url.path.hasSuffix("/messages") {
            url = url.appendingPathComponent("messages")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var messages: [[String: String]] = []
        messages.append(["role": "user", "content": req.userPrompt])

        var body: [String: Any] = [
            "model": req.model,
            "max_tokens": req.maxTokens,
            "messages": messages,
        ]
        if let sys = req.systemPrompt, !sys.isEmpty {
            body["system"] = sys
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    // MARK: OpenAI / OpenAI-compatible

    private static func buildOpenAI(
        provider: AIProvider,
        endpoint: URL,
        apiKey: String?,
        req: AICompletionRequest
    ) throws -> URLRequest {
        var url = endpoint
        if !url.path.hasSuffix("/chat/completions") {
            url = url.appendingPathComponent("chat/completions")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        } else if provider == .openai {
            throw AIError.invalidResponse("OpenAI requires an API key — set one in Settings → AI")
        }

        var messages: [[String: String]] = []
        if let sys = req.systemPrompt, !sys.isEmpty {
            messages.append(["role": "system", "content": sys])
        }
        messages.append(["role": "user", "content": req.userPrompt])

        let body: [String: Any] = [
            "model": req.model,
            "max_tokens": req.maxTokens,
            "messages": messages,
            "stream": false,
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }
}

// MARK: - Response parsing

extension AIProvider {
    /// Pull the assistant text out of a successful response body. Each
    /// provider has its own JSON shape, so we dispatch on `self`.
    func parseResponseText(_ data: Data) throws -> String {
        switch self {
        case .anthropic:           return try Self.parseAnthropic(data)
        case .openai, .localOpenAICompat:
            return try AIClient.parseChatResponse(data)   // existing OpenAI parser
        }
    }

    /// Anthropic's `/v1/messages` returns `{ "content": [ { "type":
    /// "text", "text": "…" }, … ] }`. We concatenate every `text`
    /// block in order so multi-block responses still render cleanly.
    private static func parseAnthropic(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse("Anthropic: top-level JSON not an object")
        }
        if let errorObj = json["error"] as? [String: Any],
           let msg = errorObj["message"] as? String {
            throw AIError.serverError(status: -1, body: msg)
        }
        guard let content = json["content"] as? [[String: Any]] else {
            throw AIError.invalidResponse("Anthropic: missing `content` array")
        }
        let parts: [String] = content.compactMap { block in
            guard let type = block["type"] as? String, type == "text" else { return nil }
            return block["text"] as? String
        }
        guard !parts.isEmpty else {
            throw AIError.invalidResponse("Anthropic: no text blocks in content")
        }
        return parts.joined(separator: "\n\n")
    }
}
