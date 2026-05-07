# Changelog

All notable changes to PicaMD are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning
is [SemVer](https://semver.org/).

## [0.8.0-alpha] — 2026-05-07

First public release.

### Editor

- Single-view live preview — markup markers (`**`, `*`, `~~`, `==`,
  `` ` ``, `#`, `>`, `[]()`, math `$`) become invisible as you type
  and reappear when the cursor lands on them. Native `NSTextView`,
  not a CodeMirror-in-WebView.
- Block overlays for tables, images, KaTeX math (offline-bundled),
  and Mermaid diagrams (downloaded on first use). Lazy-render
  WebView pool caps RAM at ~540 MB on a 50-block stress doc.
- Outline sidebar with cursor auto-tracking. Frontmatter bar with
  title and tag chips. Footnote tooltips on `[^id]` hover.
- Tabs (`⌘T`), Focus mode (`⌃⌘F`), Typewriter mode (`⌃⌘Y`),
  Command palette (`⌘⇧P`).

### Theme system

- 3 built-in presets: Stock+, Editorial, Tahoe.
- 4 palettes: White, Off-White, Dark Grey, OLED. 7 accent colours.
- Body / heading font, heading scale, code-block style, hairline
  rule, status bar — all toggleable in `⌘,` Settings.
- Palette is independent of macOS Light/Dark Mode (use the White
  palette while macOS is in Dark Mode if you want).

### AI assistance (opt-in)

- Multi-provider: **Anthropic Claude**, **OpenAI**, or any
  **local OpenAI-compatible server** (LM Studio, Ollama, llama.cpp,
  vLLM, Groq, etc.).
- API keys stored in the macOS Keychain.
- 9 starter prompt presets bound to `⌃⌘1`–`⌃⌘9` (clean Markdown,
  summarize, rewrite, fix grammar, translate, …). Fully editable
  in Settings → AI → Presets. Add your own prompts.
- `⌃Space` opens a fuzzy picker over all presets.
- 5 insertion modes: replace selection, append below, blockquote,
  HTML comment, popover-only.
- Off by default. No data leaves your machine unless you configure
  a cloud endpoint and trigger a request.

### Claude Code MCP server

- Embedded `picamd-mcp` sidecar (`Contents/Resources/picamd-mcp`)
  exposes every open document to Claude Code through 8 tools:
  `workspace.openDocuments`, `workspace.search`,
  `document.metadata`, `document.outline`, `document.readLines`,
  `document.readSection`, `document.replaceLines`,
  `document.appendText`.
- Token-efficient: Claude can call `outline()` + `readSection()`
  instead of re-reading the whole file each pass — typically 10×
  token savings on edit loops.
- Add to `~/.config/claude-code/mcp.json`:
  ```json
  {
    "mcpServers": {
      "picamd": {
        "command": "/Applications/PicaMD.app/Contents/Resources/picamd-mcp"
      }
    }
  }
  ```

### macOS integration

- Quick-Look extension for `.md` files (Spacebar in Finder shows
  a styled preview). Render currently blocked on getting a paid
  Apple Developer ID for proper signing — extension is wired and
  registers correctly; only signing prevents the host from loading
  it. Resolves with v1.0.
- Spotlight indexing via CoreSpotlight (every opened/saved
  document gets frontmatter title + tags + body preview).
- Services menu: "Open Selection in PicaMD" lifts text from any
  other app into a fresh PicaMD doc.
- File → Export As… HTML (in-process, includes KaTeX/Mermaid/
  footnotes), PDF / DOCX / EPUB via user-installed `pandoc`.
- Auto-update via Sparkle 2 (EdDSA-signed appcast).

### Distribution

- `release.sh` produces `dist/PicaMD-<version>.zip` with ad-hoc
  signing today, ready to switch to Developer ID notarization
  when paid credentials land.
- GitHub Actions release workflow on tag push: build, sign, zip,
  generate release notes, upload .zip + SHA-256 checksum.
- 184 unit tests, 9.8 MB bundle, only Apple system libraries
  linked plus the Sparkle framework.

### Known limitations

- Quick-Look render is blocked on paid Apple Developer ID
  (auto-resolves with v1.0).
- Ad-hoc signing means first launch shows macOS's "can't be
  opened" warning — right-click → Open works around it once.
- Streaming AI responses (incremental insertion) is planned
  but not in 0.8.0.

[0.8.0-alpha]: https://github.com/michiwickman/picamd/releases/tag/v0.8.0-alpha
