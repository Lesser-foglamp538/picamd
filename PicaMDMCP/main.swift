import Foundation

/// `picamd-mcp` — sidecar binary that speaks the **Model Context
/// Protocol** over stdio so Claude Code (and any other MCP client)
/// can read and edit the documents the user has open in PicaMD.
///
/// Architecture in two sentences: the main app maintains a JSON file
/// at `~/Library/Application Support/PicaMD/active-documents.json`
/// listing every open doc; this sidecar reads that file plus the
/// docs themselves, and exposes them through MCP tools. No XPC, no
/// sockets — one shared file is the entire bridge.
///
/// Lifecycle: Claude Code spawns this process when an MCP server
/// matching `picamd` is configured. It reads JSON-RPC requests from
/// stdin, writes responses to stdout, and logs to stderr (which
/// Claude Code surfaces in its server diagnostics).

let server = MCPServer()
server.run()
