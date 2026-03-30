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
                VStack(spacing: 10) {
                    ForEach(PropertyRegistry.definitions(for: tab)) { definition in
                        PropertyRow(definition: definition, viewModel: viewModel)
                    }
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Property Row

private struct PropertyRow: View {
    let definition: CSSPropertyDefinition
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        let isUsed = viewModel.isPropertyUsed(definition)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.title)
                        .font(.subheadline.weight(.medium))
                    Text(definition.name)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isUsed {
                    Text("Unused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    viewModel.removeProperty(definition)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(!isUsed)
                .help("Remove property")
            }

            controlView
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(isUsed ? 0.08 : 0.03), lineWidth: 1)
        )
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
            ), axis: .vertical)
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)

        case .color:
            ColorPropertyControl(definition: definition, viewModel: viewModel)

        case let .option(options):
            Picker(definition.title, selection: Binding(
                get: {
                    let current = viewModel.rawValue(for: definition)
                    return current.isEmpty ? definition.placeholder : current
                },
                set: { viewModel.updateProperty(definition, value: $0) }
            )) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)

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

                Picker("Unit", selection: Binding(
                    get: { viewModel.measurementUnit(for: definition) },
                    set: { unit in
                        let number = viewModel.measurementNumber(for: definition)
                        viewModel.updateMeasurementProperty(definition, numberOrRaw: number, unit: unit)
                    }
                )) {
                    ForEach(units, id: \.self) { unit in
                        Text(unit.isEmpty ? "unitless" : unit).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
            }
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
                    textValue = newText
                    viewModel.updateProperty(definition, value: newText)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .onAppear { textValue = rawValue }
            .onChange(of: rawValue) { _, newRaw in
                if !isEditingText { textValue = newRaw }
            }
            .onSubmit { isEditingText = false }
        }
    }
}

// MARK: - Variables Inspector

private struct VariablesInspectorView: View {
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

                ForEach(viewModel.rootVariables) { variable in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(variable.name)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.removeVariable(name: variable.name)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }

                        TextField("Value", text: Binding(
                            get: { variable.value },
                            set: { viewModel.updateVariable(name: variable.name, value: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Variable")
                        .font(.headline)

                    TextField("--token-name", text: $viewModel.newVariableName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Value", text: $viewModel.newVariableValue)
                        .textFieldStyle(.roundedBorder)

                    Button("Add Variable") {
                        viewModel.addVariable()
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(12)
        }
    }
}
