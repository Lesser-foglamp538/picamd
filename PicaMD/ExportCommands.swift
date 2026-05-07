import SwiftUI

/// File-menu entries for exporting the active document. HTML is
/// always available (in-process render); PDF / DOCX / EPUB go
/// through pandoc and disable themselves automatically when the
/// pandoc binary isn't on the user's machine.
struct ExportCommands: Commands {
    @FocusedValue(\.activeDocumentContext) private var doc: ActiveDocumentContext?

    /// Cached at startup. We deliberately don't watch for pandoc
    /// installs at runtime — if the user runs `brew install pandoc`,
    /// they need to relaunch PicaMD to pick it up. That's vanishingly
    /// rare in practice, and re-locating on every menu open is
    /// noticeable on slow `$PATH` setups (Process spawn ~30 ms).
    private static let pandocAvailable: Bool = PandocBridge.locate() != nil

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Menu("Export As…") {
                Button("HTML…") {
                    if let d = doc {
                        ExportCoordinator.exportHTML(
                            source: d.source,
                            documentName: d.filename,
                            paletteForStyling: d.palette
                        )
                    }
                }
                .disabled(doc == nil)

                Divider()

                Button(Self.pandocAvailable ? "PDF (via pandoc)…" : "PDF (pandoc not installed)…") {
                    if let d = doc {
                        ExportCoordinator.exportViaPandoc(
                            source: d.source,
                            documentName: d.filename,
                            format: .pdf
                        )
                    }
                }
                .disabled(doc == nil)

                Button(Self.pandocAvailable ? "Microsoft Word (.docx)…" : "Microsoft Word (.docx, pandoc not installed)…") {
                    if let d = doc {
                        ExportCoordinator.exportViaPandoc(
                            source: d.source,
                            documentName: d.filename,
                            format: .docx
                        )
                    }
                }
                .disabled(doc == nil)

                Button(Self.pandocAvailable ? "EPUB…" : "EPUB (pandoc not installed)…") {
                    if let d = doc {
                        ExportCoordinator.exportViaPandoc(
                            source: d.source,
                            documentName: d.filename,
                            format: .epub
                        )
                    }
                }
                .disabled(doc == nil)
            }
        }
    }
}
