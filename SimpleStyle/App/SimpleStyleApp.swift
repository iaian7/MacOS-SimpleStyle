import SwiftUI

@main
struct SimpleStyleApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { CSSDocument() }) { configuration in
            RootDocumentView(document: configuration.document)
        }
    }
}
