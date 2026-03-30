import SwiftUI
import UniformTypeIdentifiers

final class CSSDocument: ReferenceFileDocument, ObservableObject {
    static var readableContentTypes: [UTType] {
        [UTType.cssStylesheet]
    }

    @Published var text: String

    init(text: String = CSSDocument.defaultText) {
        self.text = text
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        self.text = text
    }

    func snapshot(contentType: UTType) throws -> String {
        text
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }

    static let defaultText = """
    :root {
        --accent-color: #7c3aed;
        --card-radius: 18px;
    }

    body {
        color: #111827;
        font-family: Inter, sans-serif;
    }

    .card {
        background-color: rgba(255, 255, 255, 0.92);
        border-radius: var(--card-radius);
        box-shadow: 0 18px 40px rgba(15, 23, 42, 0.16);
        padding: 24px;
    }

    .card__title {
        color: var(--accent-color);
        font-size: 1.5rem;
        font-weight: 700;
        margin-bottom: 12px;
    }
    """
}

extension UTType {
    static var cssStylesheet: UTType {
        UTType(filenameExtension: "css") ?? .plainText
    }
}
