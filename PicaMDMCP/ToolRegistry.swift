import Foundation

/// Registry of MCP tool implementations. Each tool exposes a JSON-
/// schema describing its arguments and an `invoke` closure that
/// executes the work and returns a result dictionary.
///
/// The list is built once at startup (see `installDefaults`) and
/// stays static — the user can't add/remove tools at runtime; the
/// surface is what we ship.
final class ToolRegistry {
    /// One MCP tool entry. Spec at https://modelcontextprotocol.io
    struct Tool {
        let name: String
        let description: String
        let inputSchema: [String: Any]
        let invoke: ([String: Any]) throws -> Any
    }

    private var tools: [String: Tool] = [:]

    func register(_ tool: Tool) {
        tools[tool.name] = tool
    }

    // MARK: - tools/list

    /// Build the JSON-RPC result for an MCP `tools/list` request.
    /// Format:
    ///   { "tools": [ { "name", "description", "inputSchema" }, … ] }
    func toolsListResult() -> [String: Any] {
        let serialised: [[String: Any]] = tools.values
            .sorted { $0.name < $1.name }
            .map { tool in
                return [
                    "name": tool.name,
                    "description": tool.description,
                    "inputSchema": tool.inputSchema,
                ]
            }
        return ["tools": serialised]
    }

    // MARK: - tools/call

    /// Dispatch a `tools/call` request to the matching tool. The MCP
    /// `tools/call` payload looks like:
    ///   { "name": "…", "arguments": { … } }
    /// We return the standard MCP content-block shape:
    ///   { "content": [ { "type": "text", "text": "…" } ] }
    func invoke(params: [String: Any]) throws -> [String: Any] {
        guard let name = params["name"] as? String else {
            throw MCPError("missing tool name")
        }
        guard let tool = tools[name] else {
            throw MCPError("unknown tool: \(name)")
        }
        let args = params["arguments"] as? [String: Any] ?? [:]

        let result = try tool.invoke(args)
        // MCP requires every tools/call result to be a content array.
        // We always emit text-content and stringify whatever the tool
        // returned — this keeps the surface simple, and MCP clients
        // can re-parse the JSON if they want structured fields.
        let text: String
        if let s = result as? String {
            text = s
        } else if JSONSerialization.isValidJSONObject(result),
                  let data = try? JSONSerialization.data(
                      withJSONObject: result,
                      options: [.prettyPrinted, .sortedKeys]
                  ),
                  let s = String(data: data, encoding: .utf8) {
            text = s
        } else {
            text = "\(result)"
        }
        return [
            "content": [
                ["type": "text", "text": text],
            ],
        ]
    }
}

// MARK: - Error type

struct MCPError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Default tool installation

extension ToolRegistry {
    /// Install the full PicaMD tool surface. Implementations live in
    /// `Tools.swift` so the registry stays focused on routing.
    func installDefaults() {
        register(WorkspaceTools.openDocuments())
        register(WorkspaceTools.search())
        register(DocumentTools.metadata())
        register(DocumentTools.outline())
        register(DocumentTools.readLines())
        register(DocumentTools.readSection())
        register(DocumentTools.replaceLines())
        register(DocumentTools.appendText())
    }
}
