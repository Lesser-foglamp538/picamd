import Foundation
import AppKit
import UniformTypeIdentifiers

/// Helpers for managing the `./assets/` folder next to a Markdown file.
enum MarkdownAssets {

    /// Result of saving an image into a document's assets folder.
    struct SavedImage {
        let absoluteURL: URL
        /// Path suitable for embedding into Markdown — relative to the
        /// document, e.g. `./assets/photo.png`.
        let markdownPath: String
        /// Optional alt-text derived from the filename.
        let altText: String
    }

    /// Save an image from a source file URL into the document's
    /// `./assets/` folder. If a file with the same name already exists,
    /// a numeric suffix (`-2`, `-3`, ...) is appended.
    static func copyImage(from sourceURL: URL, nextTo documentURL: URL?) throws -> SavedImage? {
        guard let documentURL = documentURL else { return nil }
        let assetsDir = documentURL.deletingLastPathComponent().appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let dest = uniqueDestination(in: assetsDir, baseName: baseName, ext: ext)
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return SavedImage(
            absoluteURL: dest,
            markdownPath: "./assets/\(dest.lastPathComponent)",
            altText: baseName
        )
    }

    /// Save raw image data (PNG / TIFF / JPEG) into the document's
    /// `./assets/` folder. Used for screenshot pastes.
    static func saveImageData(_ data: Data,
                               kind: ImageKind,
                               nextTo documentURL: URL?) throws -> SavedImage? {
        guard let documentURL = documentURL else { return nil }
        let assetsDir = documentURL.deletingLastPathComponent().appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter.compactString(from: Date())
        let baseName: String
        switch kind {
        case .screenshot: baseName = "Screenshot-\(timestamp)"
        case .pasted:     baseName = "Pasted-\(timestamp)"
        }
        let dest = uniqueDestination(in: assetsDir, baseName: baseName, ext: kind.fileExtension)
        try data.write(to: dest)
        return SavedImage(
            absoluteURL: dest,
            markdownPath: "./assets/\(dest.lastPathComponent)",
            altText: baseName
        )
    }

    enum ImageKind {
        case screenshot
        case pasted

        var fileExtension: String {
            switch self {
            case .screenshot, .pasted: return "png"
            }
        }
    }

    /// Build a Markdown image-syntax string for a saved image.
    static func markdownSyntax(for image: SavedImage) -> String {
        return "![\(image.altText)](\(image.markdownPath))"
    }

    // MARK: - Helpers

    private static func uniqueDestination(in dir: URL, baseName: String, ext: String) -> URL {
        let fm = FileManager.default
        let extPart = ext.isEmpty ? "" : ".\(ext)"
        var candidate = dir.appendingPathComponent("\(baseName)\(extPart)")
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(baseName)-\(n)\(extPart)")
            n += 1
        }
        return candidate
    }
}

private extension ISO8601DateFormatter {
    /// Builds a fresh formatter on each call (cheap, and avoids the
    /// Sendable-static-let dance under Swift 6 strict concurrency).
    /// Filename-safe: `:` is replaced with `-`.
    static func compactString(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime]
        return f.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}

extension UTType {
    /// Image content types we recognise when reading from the pasteboard
    /// or a file drop.
    static let supportedImageTypes: [UTType] = [
        .png, .jpeg, .gif, .tiff, .heic, .bmp, .webP
    ]

    static func isImage(_ type: UTType) -> Bool {
        supportedImageTypes.contains { type.conforms(to: $0) }
    }
}
