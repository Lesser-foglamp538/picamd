import XCTest
@testable import PicaMD

final class AIClientTests: XCTestCase {

    // MARK: - parseChatResponse (OpenAI shape)

    func testParseStandardOpenAIResponse() throws {
        let json = """
        {
          "id": "chatcmpl-1",
          "object": "chat.completion",
          "choices": [
            {
              "index": 0,
              "message": { "role": "assistant", "content": "Hello, world!" },
              "finish_reason": "stop"
            }
          ]
        }
        """.data(using: .utf8)!
        let result = try AIClient.parseChatResponse(json)
        XCTAssertEqual(result, "Hello, world!")
    }

    func testParseLegacyTextField() throws {
        // Some llama.cpp builds return `text` instead of `message.content`.
        let json = """
        {
          "choices": [
            { "text": "fallback content" }
          ]
        }
        """.data(using: .utf8)!
        let result = try AIClient.parseChatResponse(json)
        XCTAssertEqual(result, "fallback content")
    }

    func testParseErrorObject() {
        let json = """
        {
          "error": { "message": "model not found", "type": "invalid_request" }
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try AIClient.parseChatResponse(json)) { error in
            guard case AIError.serverError(_, let body) = error else {
                XCTFail("Expected .serverError, got \(error)")
                return
            }
            XCTAssertTrue(body.contains("model not found"))
        }
    }

    func testParseRejectsTopLevelArray() {
        let json = "[1, 2, 3]".data(using: .utf8)!
        XCTAssertThrowsError(try AIClient.parseChatResponse(json))
    }

    func testParseRejectsEmptyChoices() {
        let json = #"{"choices": []}"#.data(using: .utf8)!
        XCTAssertThrowsError(try AIClient.parseChatResponse(json))
    }

    func testParseRejectsMissingContent() {
        let json = """
        { "choices": [ { "message": { "role": "assistant" } } ] }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try AIClient.parseChatResponse(json))
    }

    // MARK: - parseAnthropicResponse

    func testParseAnthropicSingleTextBlock() throws {
        let json = """
        {
          "id": "msg_1",
          "type": "message",
          "content": [
            { "type": "text", "text": "Hi from Claude." }
          ],
          "model": "claude-sonnet-4-6"
        }
        """.data(using: .utf8)!
        let result = try AIProvider.anthropic.parseResponseText(json)
        XCTAssertEqual(result, "Hi from Claude.")
    }

    func testParseAnthropicMultipleBlocksConcatenated() throws {
        let json = """
        {
          "content": [
            { "type": "text", "text": "First." },
            { "type": "text", "text": "Second." }
          ]
        }
        """.data(using: .utf8)!
        let result = try AIProvider.anthropic.parseResponseText(json)
        XCTAssertEqual(result, "First.\n\nSecond.")
    }

    func testParseAnthropicErrorObject() {
        let json = """
        { "error": { "message": "rate limit exceeded", "type": "rate_limit_error" } }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try AIProvider.anthropic.parseResponseText(json))
    }

    func testParseAnthropicNonText() {
        // No `text` block → no usable response.
        let json = """
        { "content": [ { "type": "tool_use", "name": "x", "input": {} } ] }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try AIProvider.anthropic.parseResponseText(json))
    }

    // MARK: - URL parsing

    func testInitRejectsInvalidEndpoint() {
        XCTAssertNil(AIClient(provider: .openai, endpointString: "not a url",
                               model: "m", apiKey: "k"))
        XCTAssertNil(AIClient(provider: .openai, endpointString: "",
                               model: "m", apiKey: "k"))
        XCTAssertNil(AIClient(provider: .openai, endpointString: "/no/scheme",
                               model: "m", apiKey: "k"))
    }

    func testInitAcceptsLocalhost() {
        let c = AIClient(provider: .localOpenAICompat,
                          endpointString: "http://localhost:1234/v1",
                          model: "m",
                          apiKey: nil)
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.endpoint.host, "localhost")
        XCTAssertEqual(c?.endpoint.port, 1234)
    }
}

// MARK: - AIConfig

final class AIConfigTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "PicaMD.AIConfigTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsAreSafelyOff() {
        let cfg = AIConfig.default
        XCTAssertFalse(cfg.enabled, "AI must be off by default — opt-in only")
        XCTAssertEqual(cfg.defaultProvider, .anthropic)
        XCTAssertEqual(cfg.endpoint(for: .anthropic),
                       "https://api.anthropic.com/v1")
        XCTAssertEqual(cfg.endpoint(for: .openai),
                       "https://api.openai.com/v1")
        XCTAssertTrue(cfg.endpoint(for: .localOpenAICompat).hasPrefix("http://localhost"))
    }

    func testRoundtripSaveAndLoad() {
        var cfg = AIConfig.default
        cfg.enabled = true
        cfg.defaultProvider = .openai
        cfg.setEndpoint("https://api.groq.com/openai/v1", for: .openai)
        cfg.setModel("llama-3.1-70b", for: .openai)
        cfg.save(to: defaults)

        let loaded = AIConfig.load(defaults: defaults)
        XCTAssertTrue(loaded.enabled)
        XCTAssertEqual(loaded.defaultProvider, .openai)
        XCTAssertEqual(loaded.endpoint(for: .openai),
                       "https://api.groq.com/openai/v1")
        XCTAssertEqual(loaded.model(for: .openai), "llama-3.1-70b")
        XCTAssertEqual(loaded.endpoint(for: .anthropic),
                       AIProvider.anthropic.defaultEndpoint)
    }

    func testV1MigrationLiftsOldKeysToProviderShape() {
        // Simulate the old-style flat keys from the original AI hook.
        defaults.set(true, forKey: "PicaMD.ai.enabled")
        defaults.set("http://10.0.0.5:11434/v1", forKey: "PicaMD.ai.endpointURL")
        defaults.set("qwen2.5", forKey: "PicaMD.ai.model")

        let loaded = AIConfig.load(defaults: defaults)
        XCTAssertTrue(loaded.enabled)
        XCTAssertEqual(loaded.defaultProvider, .localOpenAICompat,
                       "v1 only had a local endpoint — migrate to localOpenAICompat")
        XCTAssertEqual(loaded.endpoint(for: .localOpenAICompat),
                       "http://10.0.0.5:11434/v1")
        XCTAssertEqual(loaded.model(for: .localOpenAICompat), "qwen2.5")
    }
}

// MARK: - AIRequestBuilder

final class AIRequestBuilderTests: XCTestCase {

    func testAnthropicRequestShape() throws {
        let url = URL(string: "https://api.anthropic.com/v1")!
        let req = AICompletionRequest(
            userPrompt: "hello",
            systemPrompt: "be concise",
            model: "claude-sonnet-4-6"
        )
        let urlReq = try AIRequestBuilder.build(
            provider: .anthropic,
            endpoint: url,
            apiKey: "sk-ant-123",
            request: req
        )

        XCTAssertTrue(urlReq.url?.path.hasSuffix("/messages") ?? false)
        XCTAssertEqual(urlReq.value(forHTTPHeaderField: "x-api-key"), "sk-ant-123")
        XCTAssertEqual(urlReq.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")

        let body = try XCTUnwrap(urlReq.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "claude-sonnet-4-6")
        XCTAssertEqual(json["system"] as? String, "be concise")
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"], "user")
        XCTAssertEqual(messages[0]["content"], "hello")
    }

    func testAnthropicMissingKeyThrows() {
        let url = URL(string: "https://api.anthropic.com/v1")!
        let req = AICompletionRequest(userPrompt: "x", model: "claude-sonnet-4-6")
        XCTAssertThrowsError(try AIRequestBuilder.build(
            provider: .anthropic,
            endpoint: url,
            apiKey: nil,
            request: req
        ))
    }

    func testOpenAIRequestShape() throws {
        let url = URL(string: "https://api.openai.com/v1")!
        let req = AICompletionRequest(
            userPrompt: "hi",
            systemPrompt: "be terse",
            model: "gpt-4o-mini"
        )
        let urlReq = try AIRequestBuilder.build(
            provider: .openai,
            endpoint: url,
            apiKey: "sk-456",
            request: req
        )

        XCTAssertTrue(urlReq.url?.path.hasSuffix("/chat/completions") ?? false)
        XCTAssertEqual(urlReq.value(forHTTPHeaderField: "Authorization"), "Bearer sk-456")

        let body = try XCTUnwrap(urlReq.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], "be terse")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "hi")
        XCTAssertEqual(json["stream"] as? Bool, false)
    }

    func testLocalProviderDoesNotRequireKey() throws {
        let url = URL(string: "http://localhost:1234/v1")!
        let req = AICompletionRequest(userPrompt: "hi", model: "local-model")
        let urlReq = try AIRequestBuilder.build(
            provider: .localOpenAICompat,
            endpoint: url,
            apiKey: nil,
            request: req
        )
        XCTAssertNil(urlReq.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(urlReq.url?.path.hasSuffix("/chat/completions") ?? false)
    }

    func testOpenAIWithoutKeyThrows() {
        let url = URL(string: "https://api.openai.com/v1")!
        let req = AICompletionRequest(userPrompt: "x", model: "gpt-4o-mini")
        XCTAssertThrowsError(try AIRequestBuilder.build(
            provider: .openai,
            endpoint: url,
            apiKey: nil,
            request: req
        ))
    }
}

// MARK: - AIPreset

final class AIPresetTests: XCTestCase {

    func testResolvePromptSubstitutesPlaceholder() {
        let preset = AIPreset(
            id: UUID(),
            name: "test",
            systemPrompt: nil,
            userPromptTemplate: "Translate this: {{selection}}",
            insertionMode: .replaceSelection,
            hotkey: nil
        )
        XCTAssertEqual(
            preset.resolvePrompt(selection: "Hallo"),
            "Translate this: Hallo"
        )
    }

    func testResolvePromptAppendsWhenPlaceholderMissing() {
        let preset = AIPreset(
            id: UUID(),
            name: "test",
            systemPrompt: nil,
            userPromptTemplate: "Summarize the following:",
            insertionMode: .replaceSelection,
            hotkey: nil
        )
        XCTAssertEqual(
            preset.resolvePrompt(selection: "long text"),
            "Summarize the following:\n\nlong text"
        )
    }

    func testStarterPresetsCoverHotkeys1Through9() {
        let defaults = AIPreset.defaults
        let assigned = Set(defaults.compactMap { $0.hotkey })
        XCTAssertEqual(assigned, Set(1...9))
    }

    func testInsertionModeIsCodableRoundtrip() throws {
        let preset = AIPreset(
            id: UUID(),
            name: "x",
            systemPrompt: "sys",
            userPromptTemplate: "{{selection}}",
            insertionMode: .asBlockquote,
            hotkey: 3
        )
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(AIPreset.self, from: data)
        XCTAssertEqual(decoded, preset)
    }
}
