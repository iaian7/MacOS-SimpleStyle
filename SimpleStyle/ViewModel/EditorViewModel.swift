import AppKit
import Combine
import Foundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var previewURLString = "http://localhost:3000"
    @Published var previewCSS = ""
    @Published var reloadToken = UUID()
    var selectedRange = NSRange(location: 0, length: 0)
    @Published var currentRule: CSSRuleContext?
    @Published var selectedTab: InspectorTabKey = .layout
    @Published var rootVariables: [CSSDeclaration] = []
    @Published var newVariableName = ""
    @Published var newVariableValue = ""

    let document: CSSDocument

    private var cancellables: Set<AnyCancellable> = []
    private var debounceTask: Task<Void, Never>?
    private weak var textView: NSTextView?

    init(document: CSSDocument) {
        self.document = document
        self.previewCSS = document.text

        document.$text
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self else { return }
                self.refreshDerivedState(using: text)
            }
            .store(in: &cancellables)
    }

    func start() {
        refreshDerivedState(using: document.text)
    }

    func register(textView: NSTextView) {
        self.textView = textView
    }

    func handleTextChanged(_ newText: String) {
        guard document.text != newText else {
            return
        }

        document.text = newText
        scheduleDebouncedPreviewUpdate()
    }

    func handleSelectionChanged(_ newRange: NSRange) {
        guard NSEqualRanges(selectedRange, newRange) == false else {
            return
        }

        selectedRange = newRange
        DispatchQueue.main.async { [weak self] in
            self?.refreshCurrentRule(scrollIntoView: true)
        }
    }

    func loadPreview() {
        reloadToken = UUID()
    }

    func rawValue(for definition: CSSPropertyDefinition) -> String {
        currentRule?.declaration(named: definition.name)?.value ?? ""
    }

    func isPropertyUsed(_ definition: CSSPropertyDefinition) -> Bool {
        currentRule?.declaration(named: definition.name) != nil
    }

    func updateProperty(_ definition: CSSPropertyDefinition, value: String) {
        guard let currentRule else {
            return
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        document.text = CSSEngine.upsertProperty(named: definition.name, value: trimmed, in: document.text, context: currentRule)
        previewCSS = document.text
        refreshDerivedState(using: document.text)
        scrollCurrentRuleIntoView()
    }

    func removeProperty(_ definition: CSSPropertyDefinition) {
        guard let currentRule else {
            return
        }

        document.text = CSSEngine.removeProperty(named: definition.name, in: document.text, context: currentRule)
        previewCSS = document.text
        refreshDerivedState(using: document.text)
        scrollCurrentRuleIntoView()
    }

    func addProperty(_ definition: CSSPropertyDefinition) {
        switch definition.control {
        case let .measurement(units):
            updateMeasurementProperty(definition, numberOrRaw: definition.placeholder, unit: units.first ?? "")
        default:
            updateProperty(definition, value: definition.placeholder)
        }
    }

    func measurementNumber(for definition: CSSPropertyDefinition) -> String {
        let raw = rawValue(for: definition)
        return CSSEngine.parseMeasurement(raw)?.number ?? raw
    }

    func measurementUnit(for definition: CSSPropertyDefinition) -> String {
        let raw = rawValue(for: definition)
        if let parsed = CSSEngine.parseMeasurement(raw) {
            return parsed.unit
        }

        if case let .measurement(units) = definition.control {
            return units.first ?? ""
        }

        return ""
    }

    func updateMeasurementProperty(_ definition: CSSPropertyDefinition, numberOrRaw: String, unit: String) {
        let value = CSSEngine.stringifyMeasurement(numberOrRaw: numberOrRaw, unit: unit)
        updateProperty(definition, value: value)
    }

    func updateVariable(name: String, value: String) {
        let existingRoot = CSSEngine.findRootRule(in: document.text)
        if let existingRoot {
            document.text = CSSEngine.upsertProperty(named: name, value: value, in: document.text, context: existingRoot)
        } else {
            let created = CSSEngine.createRootRule(in: document.text)
            document.text = created.text
            if let rootRule = created.rule {
                document.text = CSSEngine.upsertProperty(named: name, value: value, in: document.text, context: rootRule)
            }
        }

        previewCSS = document.text
        refreshDerivedState(using: document.text)
    }

    func removeVariable(name: String) {
        guard let rootRule = CSSEngine.findRootRule(in: document.text) else {
            return
        }

        document.text = CSSEngine.removeProperty(named: name, in: document.text, context: rootRule)
        previewCSS = document.text
        refreshDerivedState(using: document.text)
    }

    func addVariable() {
        let trimmedName = newVariableName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = newVariableValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedValue.isEmpty else {
            return
        }

        let propertyName = trimmedName.hasPrefix("--") ? trimmedName : "--\(trimmedName)"
        updateVariable(name: propertyName, value: trimmedValue)
        newVariableName = ""
        newVariableValue = ""
        selectedTab = .variables
    }

    private func refreshDerivedState(using text: String) {
        if previewCSS.isEmpty || previewCSS != text {
            previewCSS = text
        }

        rootVariables = CSSEngine.findRootRule(in: text)?.declarations.filter { $0.name.hasPrefix("--") } ?? []
        DispatchQueue.main.async { [weak self] in
            self?.refreshCurrentRule(scrollIntoView: false)
        }
    }

    private func refreshCurrentRule(scrollIntoView: Bool) {
        let location = min(max(selectedRange.location, 0), max(document.text.utf16.count - 1, 0))
        currentRule = CSSEngine.resolveRule(in: document.text, at: location)
        if scrollIntoView {
            scrollCurrentRuleIntoView()
        }
    }

    private func scrollCurrentRuleIntoView() {
        guard let textView, let currentRule else {
            return
        }

        textView.scrollRangeToVisible(currentRule.blockRange)
    }

    private func scheduleDebouncedPreviewUpdate() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.previewCSS = self.document.text
        }
    }
}
