import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var markdown: UTType {
        UTType(importedAs: "net.daringfireball.markdown")
    }
}

struct MarkdownDocument: FileDocument {
    var text: String

    init(text: String = "") {
        self.text = text
    }

    static var readableContentTypes: [UTType] { [.markdown, .plainText] }
    static var writableContentTypes: [UTType] { [.markdown, .plainText] }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Refuse non-UTF-8 input — silently swapping to an empty string
        // would let the user save a "blank" document over the original
        // bytes (data-loss). Surface the error to AppKit instead so the
        // standard "couldn't open" alert appears.
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        // Notify any open editor coordinator that we're about to write
        // to disk, so its FileWatcher can ignore the resulting
        // vnode-event. We include a per-write nonce so coordinators
        // watching DIFFERENT documents don't suppress their own
        // legitimate external-edit events when an unrelated window
        // happens to save.
        NotificationCenter.default.post(
            name: .picaMDDocumentWillWrite,
            object: nil,
            userInfo: [Self.willWriteNonceKey: UUID().uuidString,
                       Self.willWriteTextKey: text]
        )
        return FileWrapper(regularFileWithContents: data)
    }

    static let willWriteNonceKey = "PicaMDWillWriteNonce"
    static let willWriteTextKey = "PicaMDWillWriteText"
}

extension Notification.Name {
    static let picaMDDocumentWillWrite = Notification.Name("PicaMDDocumentWillWrite")
}
