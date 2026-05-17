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
    @Published var isXRayEnabled: Bool = false
    @Published var xraySelectedElement: XRayElementInfo?
    @Published var xrayMatchedRules: [CSSRuleContext] = []

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

    /// Called when the user clicks an element in the X-Ray view. Stores the
    /// element info and computes the list of matching rules. The user can then
    /// pick one of those rules from the inspector to edit it.
    func handleXRayElementSelected(_ info: XRayElementInfo) {
        xraySelectedElement = info
        let matches = CSSEngine.findRules(matching: info, in: document.text)
        xrayMatchedRules = matches

        if let first = matches.first {
            selectRule(first)
        } else {
            // No matching rule — create a new block using preferred selector.
            createNewRule(for: info)
        }
    }

    /// Selects the given rule: moves the editor caret inside it (which
    /// auto-populates the inspector via the existing selectionChanged flow).
    func selectRule(_ rule: CSSRuleContext) {
        let newRange = NSRange(location: rule.openBraceIndex + 1, length: 0)
        selectedRange = newRange
        textView?.setSelectedRange(newRange)
        refreshCurrentRuleNow(scrollIntoView: true)
    }

    private func createNewRule(for info: XRayElementInfo) {
        let selector = info.preferredSelector
        let newBlock = "\n\n\(selector) {\n}\n"
        let insertionPoint = document.text.utf16.count
        document.text.append(newBlock)
        // After the appended "\n\n<selector> {\n", caret should sit inside the braces.
        let newLocation = insertionPoint + 2 + selector.utf16.count + 3
        let newRange = NSRange(location: newLocation, length: 0)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.selectedRange = newRange
            self.textView?.setSelectedRange(newRange)
            self.refreshCurrentRuleNow(scrollIntoView: true)
            // Refresh matched rules so the new block shows up in the list
            self.xrayMatchedRules = CSSEngine.findRules(matching: info, in: self.document.text)
        }
    }

    private func refreshCurrentRuleNow(scrollIntoView: Bool) {
        refreshCurrentRule(scrollIntoView: scrollIntoView)
    }

    private func refreshDerivedState(using text: String) {
        if previewCSS.isEmpty || previewCSS != text {
            previewCSS = text
        }

        rootVariables = CSSEngine.findRootRule(in: text)?.declarations.filter { $0.name.hasPrefix("--") } ?? []
        if let element = xraySelectedElement {
            xrayMatchedRules = CSSEngine.findRules(matching: element, in: text)
        }
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
