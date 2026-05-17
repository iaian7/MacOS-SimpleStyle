import SwiftUI

struct InspectorView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Inspector")
                    .font(.headline)

                if let currentRule = viewModel.currentRule {
                    Text(currentRule.displayPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("Place the text cursor inside a selector block to edit it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.bar)

            if viewModel.xraySelectedElement != nil {
                ElementTreeView(viewModel: viewModel)
            }

            if let element = viewModel.xraySelectedElement {
                MatchedRulesListView(element: element, viewModel: viewModel)
            }

            TabView(selection: $viewModel.selectedTab) {
                ForEach(InspectorTabKey.allCases) { tab in
                    inspectorContent(for: tab)
                        .tabItem {
                            Text(tab.rawValue)
                        }
                        .tag(tab)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func inspectorContent(for tab: InspectorTabKey) -> some View {
        switch tab {
        case .variables:
            VariablesInspectorView(viewModel: viewModel)
        default:
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(PropertyRegistry.definitions(for: tab)) { definition in
                        PropertyRow(definition: definition, viewModel: viewModel)
                    }
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Element Tree

private struct ElementTreeView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Element Tree")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    viewModel.createRuleForSelectedElement()
                } label: {
                    Label("New Rule", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Create a new rule for the selected element")
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(viewModel.xrayAncestors.enumerated()), id: \.offset) { idx, ancestor in
                        treeRow(index: idx, ancestor: ancestor)
                    }
                }
            }
            .frame(maxHeight: 160)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }

    @ViewBuilder
    private func treeRow(index: Int, ancestor: XRayElementInfo) -> some View {
        let isSelected = index == viewModel.xrayAncestors.count - 1
        Button {
            viewModel.selectXRayAncestor(at: index)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "chevron.right.circle.fill" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(ancestor.displayLabel)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.leading, CGFloat(index) * 10)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Matched Rules List

private struct MatchedRulesListView: View {
    let element: XRayElementInfo
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Matched Rules")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(element.displayLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if viewModel.xrayMatchedRules.isEmpty {
                Text("No matching rules in this stylesheet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.xrayMatchedRules, id: \.openBraceIndex) { rule in
                            ruleRow(rule)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }

    @ViewBuilder
    private func ruleRow(_ rule: CSSRuleContext) -> some View {
        let isCurrent = viewModel.currentRule?.openBraceIndex == rule.openBraceIndex
        Button {
            viewModel.selectRule(rule)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                Text(rule.displayPath)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(rule.declarations.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Property Row

private struct PropertyRow: View {
    private let labelColumnWidth: CGFloat = 140
    private let unitColumnWidth: CGFloat = 96

    let definition: CSSPropertyDefinition
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        let isUsed = viewModel.isPropertyUsed(definition)

        HStack(spacing: 8) {
            Text(definition.title)
                .font(.subheadline.weight(.medium))
                .frame(width: labelColumnWidth, alignment: .leading)

            controlView
                .disabled(!isUsed)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if isUsed {
                    viewModel.removeProperty(definition)
                } else {
                    viewModel.addProperty(definition)
                }
            } label: {
                Image(systemName: isUsed ? "minus.circle" : "plus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isUsed ? Color.red : Color.accentColor)
            .help(isUsed ? "Remove property" : "Add property")
            .frame(width: 20)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: isUsed ? .controlBackgroundColor : .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(isUsed ? 0.08 : 0), lineWidth: 1)
        )
        .opacity(isUsed ? 1 : 0.55)
    }

    @ViewBuilder
    private var controlView: some View {
        switch definition.control {
        case .text:
            TextField(definition.placeholder, text: Binding(
                get: { viewModel.rawValue(for: definition) },
                set: { viewModel.updateProperty(definition, value: $0) }
            ))
            .textFieldStyle(.roundedBorder)

        case .multiline:
            TextField(definition.placeholder, text: Binding(
                get: { viewModel.rawValue(for: definition) },
                set: { viewModel.updateProperty(definition, value: $0) }
            ))
            .textFieldStyle(.roundedBorder)

        case .color:
            ColorPropertyControl(definition: definition, viewModel: viewModel)

        case let .option(options):
            let current = viewModel.rawValue(for: definition)
            let resolved = current.isEmpty ? definition.placeholder : current
            let needsCustomTag = !options.contains(resolved)
            Picker("", selection: Binding(
                get: { resolved },
                set: { viewModel.updateProperty(definition, value: $0) }
            )) {
                if needsCustomTag {
                    Text(resolved.isEmpty ? "—" : resolved).tag(resolved)
                }
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

        case let .measurement(units):
            HStack(spacing: 8) {
                TextField(definition.placeholder, text: Binding(
                    get: { viewModel.measurementNumber(for: definition) },
                    set: { newValue in
                        let unit = viewModel.measurementUnit(for: definition)
                        viewModel.updateMeasurementProperty(definition, numberOrRaw: newValue, unit: unit)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

                let currentUnit = viewModel.measurementUnit(for: definition)
                let needsCustomUnitTag = !units.contains(currentUnit)
                Picker("", selection: Binding(
                    get: { currentUnit },
                    set: { unit in
                        let number = viewModel.measurementNumber(for: definition)
                        viewModel.updateMeasurementProperty(definition, numberOrRaw: number, unit: unit)
                    }
                )) {
                    if needsCustomUnitTag {
                        Text(currentUnit.isEmpty ? "unitless" : currentUnit).tag(currentUnit)
                    }
                    ForEach(units, id: \.self) { unit in
                        Text(unit.isEmpty ? "unitless" : unit).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: unitColumnWidth)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Color Property Control

/// A ColorPicker swatch alongside a text field.
/// The picker handles #hex / rgba values; the text field accepts anything
/// including var() references and named colors.
private struct ColorPropertyControl: View {
    let definition: CSSPropertyDefinition
    @ObservedObject var viewModel: EditorViewModel

    /// Local text state so the field doesn't round-trip through Color while typing.
    @State private var textValue = ""
    @State private var isEditingText = false

    private var rawValue: String { viewModel.rawValue(for: definition) }

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: Binding(
                get: {
                    Color(cssString: rawValue) ?? .clear
                },
                set: { newColor in
                    let css = newColor.cssString
                    textValue = css
                    viewModel.updateProperty(definition, value: css)
                }
            ))
            .labelsHidden()
            .frame(width: 28, height: 28)

            TextField(definition.placeholder, text: Binding(
                get: {
                    isEditingText ? textValue : rawValue
                },
                set: { newText in
                    isEditingText = true
                    textValue = newText
                    viewModel.updateProperty(definition, value: newText)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
            .onAppear { textValue = rawValue }
            .onChange(of: rawValue) { _, newRaw in
                // Defer the local state mirror to the next runloop tick so
                // SwiftUI doesn't see two state writes in the same frame.
                guard !isEditingText, newRaw != textValue else { return }
                DispatchQueue.main.async {
                    textValue = newRaw
                }
            }
            .onSubmit { isEditingText = false }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Variables Inspector

private struct VariablesInspectorView: View {
    private let nameColumnWidth: CGFloat = 180

    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Root Variables")
                        .font(.headline)
                    Text("Edits the `:root` block and keeps custom properties available for the current stylesheet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.rootVariables.indices, id: \.self) { index in
                    let variable = viewModel.rootVariables[index]
                    HStack(spacing: 8) {
                        Text(variable.name)
                            .font(.subheadline.weight(.medium))
                            .frame(width: nameColumnWidth, alignment: .leading)

                        TextField("Value", text: Binding(
                            get: { variable.value },
                            set: { viewModel.updateVariable(name: variable.name, value: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)

                        Button {
                            viewModel.removeVariable(name: variable.name)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.red)
                        .help("Remove variable")
                        .frame(width: 20)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                }

                HStack(spacing: 8) {
                    TextField("--token-name", text: $viewModel.newVariableName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: nameColumnWidth)

                    TextField("Value", text: $viewModel.newVariableValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)

                    Button {
                        viewModel.addVariable()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                    .help("Add variable")
                    .frame(width: 20)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(12)
        }
    }
}
