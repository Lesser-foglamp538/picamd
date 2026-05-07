import AppKit
import UniformTypeIdentifiers

/// Drives the "Export As…" actions from the File menu. Each format
/// gets its own menu item so the user picks the format from the menu
/// itself — no extra "pick format" sheet, no extra clicks. Pandoc
/// formats grey themselves out automatically when pandoc isn't on
/// the system.
@MainActor
enum ExportCoordinator {

    /// Exports the active document's source string to HTML using the
    /// in-process renderer. Always available (no external dep).
    static func exportHTML(source: String,
                            documentName: String?,
                            paletteForStyling: Palette? = nil) {
        let suggested = (documentName ?? "Untitled").replacingOccurrences(of: ".md", with: "") + ".html"
        runSavePanel(
            suggestedFilename: suggested,
            allowedTypes: [.html],
            tag: "HTML"
        ) { url in
            let html = MarkdownToHTML.render(source, palette: paletteForStyling)
            do {
                try html.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                presentError(error,
                              title: "HTML export failed")
            }
        }
    }

    /// Pandoc-driven PDF export. Surfaces a "pandoc not installed"
    /// alert with a Homebrew hint instead of failing silently.
    static func exportViaPandoc(source: String,
                                 documentName: String?,
                                 format: PandocBridge.Format) {
        guard PandocBridge.locate() != nil else {
            presentPandocMissingAlert(format: format)
            return
        }
        let base = (documentName ?? "Untitled").replacingOccurrences(of: ".md", with: "")
        let suggested = "\(base).\(format.fileExtension)"
        let allowedTypes: [UTType] = {
            switch format {
            case .pdf:  return [.pdf]
            case .docx: return [UTType(filenameExtension: "docx") ?? .data]
            case .epub: return [UTType(filenameExtension: "epub") ?? .data]
            }
        }()
        runSavePanel(
            suggestedFilename: suggested,
            allowedTypes: allowedTypes,
            tag: format.displayName
        ) { url in
            // pandoc runs synchronously and can take a few seconds for
            // large docs / PDF — hop off main so the UI stays responsive,
            // then come back to surface success/errors.
            Task.detached(priority: .userInitiated) {
                do {
                    try PandocBridge.export(markdown: source, to: url, format: format)
                    await MainActor.run {
                        // Reveal in Finder so the user can verify the export.
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } catch {
                    await MainActor.run {
                        presentError(error,
                                      title: "\(format.displayName) export failed")
                    }
                }
            }
        }
    }

    // MARK: - Save panel

    private static func runSavePanel(suggestedFilename: String,
                                      allowedTypes: [UTType],
                                      tag: String,
                                      completion: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = allowedTypes
        panel.message = "Export as \(tag)"
        panel.title = "Export Document"
        panel.isExtensionHidden = false

        // Dispatch async so we don't block the menu-action chain;
        // panel runs modally on the active window.
        DispatchQueue.main.async {
            let response = panel.runModal()
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }

    // MARK: - Error UI

    private static func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func presentPandocMissingAlert(format: PandocBridge.Format) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Pandoc is required for \(format.displayName) export"
        alert.informativeText = """
        PicaMD uses pandoc to render \(format.displayName). Install it via Homebrew:

            brew install pandoc

        For PDF in particular, pandoc also needs a LaTeX engine such as
        `basictex` or `mactex`. HTML export works without pandoc.
        """
        alert.addButton(withTitle: "Copy command")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString("brew install pandoc", forType: .string)
        }
    }
}
