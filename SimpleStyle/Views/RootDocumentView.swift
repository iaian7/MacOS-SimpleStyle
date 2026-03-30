import SwiftUI

struct RootDocumentView: View {
    @ObservedObject var document: CSSDocument
    @StateObject private var viewModel: EditorViewModel

    init(document: CSSDocument) {
        self.document = document
        _viewModel = StateObject(wrappedValue: EditorViewModel(document: document))
    }

    var body: some View {
        HSplitView {
            CSSCodeEditorView(viewModel: viewModel)
                .frame(minWidth: 340, idealWidth: 420)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("http://localhost:3000", text: $viewModel.previewURLString)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            viewModel.loadPreview()
                        }

                    Button("Reload") {
                        viewModel.loadPreview()
                    }
                }
                .padding(12)
                .background(.bar)

                WebPreviewView(viewModel: viewModel)
            }
            .frame(minWidth: 420, idealWidth: 720)

            InspectorView(viewModel: viewModel)
                .frame(minWidth: 320, idealWidth: 380)
        }
        .frame(minWidth: 1220, minHeight: 760)
        .onAppear {
            viewModel.start()
        }
    }
}
