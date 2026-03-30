import AppKit
import SwiftUI

struct CSSCodeEditorView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Stylesheet")
                    .font(.headline)
                Spacer()
                if let currentRule = viewModel.currentRule {
                    Text(currentRule.displayPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Select a selector block")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.bar)

            CodeEditorRepresentable(
                text: Binding(
                    get: { viewModel.document.text },
                    set: { viewModel.handleTextChanged($0) }
                ),
                selectedRange: Binding(
                    get: { viewModel.selectedRange },
                    set: { viewModel.handleSelectionChanged($0) }
                ),
                onTextViewCreated: { textView in
                    viewModel.register(textView: textView)
                }
            )
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct CodeEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    let onTextViewCreated: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let textStorage = NSTextStorage(string: text)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.usesFindBar = true
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.delegate = context.coordinator
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        context.coordinator.textView = textView
        scrollView.documentView = textView
        onTextViewCreated(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            context.coordinator.isUpdatingFromModel = true
            let savedRange = textView.selectedRange()
            textView.string = text
            // Restore cursor position clamped to new text length
            let clampedLocation = min(savedRange.location, textView.string.utf16.count)
            textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
            context.coordinator.isUpdatingFromModel = false
        }

        if NSEqualRanges(textView.selectedRange(), selectedRange) == false {
            context.coordinator.isUpdatingSelection = true
            textView.setSelectedRange(selectedRange)
            textView.scrollRangeToVisible(selectedRange)
            context.coordinator.isUpdatingSelection = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var selectedRange: NSRange
        weak var textView: NSTextView?
        var isUpdatingFromModel = false
        var isUpdatingSelection = false

        init(text: Binding<String>, selectedRange: Binding<NSRange>) {
            _text = text
            _selectedRange = selectedRange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isUpdatingFromModel else { return }
            text = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, !isUpdatingSelection else { return }
            selectedRange = textView.selectedRange()
        }
    }
}
