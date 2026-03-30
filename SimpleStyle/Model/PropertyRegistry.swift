import Foundation

enum InspectorTabKey: String, CaseIterable, Identifiable {
    case layout = "Layout"
    case typography = "Typography"
    case effects = "Effects"
    case animation = "Animation"
    case variables = "Variables"

    var id: String { rawValue }
}

enum PropertyControlKind: Equatable {
    case text
    case color
    case measurement(units: [String])
    case option([String])
    case multiline
}

struct CSSPropertyDefinition: Identifiable, Equatable {
    let name: String
    let title: String
    let tab: InspectorTabKey
    let control: PropertyControlKind
    let placeholder: String

    var id: String { name }
}

enum PropertyRegistry {
    static let definitions: [CSSPropertyDefinition] = [
        // MARK: Layout
        .init(name: "display",               title: "Display",            tab: .layout,     control: .option(["block", "inline", "inline-block", "flex", "grid", "none"]),                          placeholder: "block"),
        .init(name: "position",              title: "Position",           tab: .layout,     control: .option(["static", "relative", "absolute", "fixed", "sticky"]),                                placeholder: "relative"),
        .init(name: "width",                 title: "Width",              tab: .layout,     control: .measurement(units: ["px", "%", "rem", "em", "vw"]),                                           placeholder: "320"),
        .init(name: "height",                title: "Height",             tab: .layout,     control: .measurement(units: ["px", "%", "rem", "em", "vh"]),                                           placeholder: "240"),
        .init(name: "min-width",             title: "Min Width",          tab: .layout,     control: .measurement(units: ["px", "%", "rem", "em", "vw"]),                                           placeholder: "200"),
        .init(name: "min-height",            title: "Min Height",         tab: .layout,     control: .measurement(units: ["px", "%", "rem", "em", "vh"]),                                           placeholder: "120"),
        .init(name: "max-width",             title: "Max Width",          tab: .layout,     control: .measurement(units: ["px", "%", "rem", "em", "vw"]),                                           placeholder: "none"),
        .init(name: "max-height",            title: "Max Height",         tab: .layout,     control: .measurement(units: ["px", "%", "rem", "em", "vh"]),                                           placeholder: "none"),
        .init(name: "margin",                title: "Margin",             tab: .layout,     control: .measurement(units: ["px", "%", "rem", "em"]),                                                 placeholder: "24"),
        .init(name: "padding",               title: "Padding",            tab: .layout,     control: .measurement(units: ["px", "%", "rem", "em"]),                                                 placeholder: "24"),
        .init(name: "gap",                   title: "Gap",                tab: .layout,     control: .measurement(units: ["px", "%", "rem", "em"]),                                                 placeholder: "12"),
        .init(name: "top",                   title: "Top",                tab: .layout,     control: .measurement(units: ["px", "%", "rem", "em"]),                                                 placeholder: "0"),
        .init(name: "right",                 title: "Right",              tab: .layout,     control: .measurement(units: ["px", "%", "rem", "em"]),                                                 placeholder: "0"),
        .init(name: "bottom",                title: "Bottom",             tab: .layout,     control: .measurement(units: ["px", "%", "rem", "em"]),                                                 placeholder: "0"),
        .init(name: "left",                  title: "Left",               tab: .layout,     control: .measurement(units: ["px", "%", "rem", "em"]),                                                 placeholder: "0"),
        .init(name: "flex-direction",        title: "Flex Direction",     tab: .layout,     control: .option(["row", "column", "row-reverse", "column-reverse"]),                                   placeholder: "row"),
        .init(name: "justify-content",       title: "Justify Content",    tab: .layout,     control: .option(["flex-start", "center", "flex-end", "space-between", "space-around", "space-evenly"]), placeholder: "center"),
        .init(name: "align-items",           title: "Align Items",        tab: .layout,     control: .option(["stretch", "flex-start", "center", "flex-end", "baseline"]),                          placeholder: "stretch"),
        .init(name: "grid-template-columns", title: "Grid Columns",       tab: .layout,     control: .multiline,                                                                                    placeholder: "repeat(3, 1fr)"),
        .init(name: "grid-template-rows",    title: "Grid Rows",          tab: .layout,     control: .multiline,                                                                                    placeholder: "auto 1fr auto"),

        // MARK: Typography
        .init(name: "color",                 title: "Text Color",         tab: .typography, control: .color,                                                                                        placeholder: "#111827"),
        .init(name: "font-family",           title: "Font Family",        tab: .typography, control: .text,                                                                                         placeholder: "Inter, sans-serif"),
        .init(name: "font-size",             title: "Font Size",          tab: .typography, control: .measurement(units: ["px", "rem", "em", "%"]),                                                 placeholder: "16"),
        .init(name: "font-weight",           title: "Font Weight",        tab: .typography, control: .option(["300", "400", "500", "600", "700", "800"]),                                           placeholder: "400"),
        .init(name: "line-height",           title: "Line Height",        tab: .typography, control: .measurement(units: ["", "px", "rem", "em", "%"]),                                            placeholder: "1.5"),
        .init(name: "letter-spacing",        title: "Letter Spacing",     tab: .typography, control: .measurement(units: ["px", "em", "rem"]),                                                      placeholder: "0"),
        .init(name: "text-align",            title: "Text Align",         tab: .typography, control: .option(["left", "center", "right", "justify"]),                                               placeholder: "left"),
        .init(name: "text-transform",        title: "Text Transform",     tab: .typography, control: .option(["none", "uppercase", "lowercase", "capitalize"]),                                     placeholder: "none"),

        // MARK: Effects
        .init(name: "background-color",      title: "Background",         tab: .effects,    control: .color,                                                                                        placeholder: "rgba(255, 255, 255, 0.85)"),
        .init(name: "border",                title: "Border",             tab: .effects,    control: .text,                                                                                         placeholder: "1px solid #d1d5db"),
        .init(name: "border-radius",         title: "Radius",             tab: .effects,    control: .measurement(units: ["px", "%", "rem"]),                                                       placeholder: "16"),
        .init(name: "box-shadow",            title: "Shadow",             tab: .effects,    control: .multiline,                                                                                    placeholder: "0 12px 32px rgba(15, 23, 42, 0.18)"),
        .init(name: "opacity",               title: "Opacity",            tab: .effects,    control: .measurement(units: [""]),                                                                     placeholder: "0.9"),
        .init(name: "transform",             title: "Transform",          tab: .effects,    control: .multiline,                                                                                    placeholder: "translateY(-4px) scale(1.01)"),
        .init(name: "overflow",              title: "Overflow",           tab: .effects,    control: .option(["visible", "hidden", "scroll", "auto"]),                                             placeholder: "visible"),

        // MARK: Animation
        .init(name: "transition",                  title: "Transition",           tab: .animation, control: .multiline,                                                                              placeholder: "all 180ms ease"),
        .init(name: "transition-duration",         title: "Transition Duration",  tab: .animation, control: .measurement(units: ["ms", "s"]),                                                       placeholder: "180"),
        .init(name: "transition-timing-function",  title: "Transition Ease",      tab: .animation, control: .option(["ease", "linear", "ease-in", "ease-out", "ease-in-out"]),                      placeholder: "ease"),
        .init(name: "animation-name",              title: "Animation Name",       tab: .animation, control: .text,                                                                                  placeholder: "pulse"),
        .init(name: "animation-duration",          title: "Animation Duration",   tab: .animation, control: .measurement(units: ["ms", "s"]),                                                       placeholder: "600"),
        .init(name: "animation-timing-function",   title: "Animation Ease",       tab: .animation, control: .option(["ease", "linear", "ease-in", "ease-out", "ease-in-out"]),                      placeholder: "ease"),
        .init(name: "animation-iteration-count",   title: "Iteration Count",      tab: .animation, control: .text,                                                                                  placeholder: "infinite"),
    ]

    static func definitions(for tab: InspectorTabKey) -> [CSSPropertyDefinition] {
        definitions.filter { $0.tab == tab }
    }
}
