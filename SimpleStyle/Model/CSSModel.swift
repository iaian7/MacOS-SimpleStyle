import Foundation

struct CSSDeclaration: Identifiable, Equatable {
    let name: String
    let value: String
    let range: NSRange
    let indentation: String

    var id: String { "\(name)-\(range.location)-\(range.length)" }
}

struct CSSRuleContext: Equatable {
    let selector: String
    let parentAtRules: [String]
    let headerRange: NSRange
    let blockRange: NSRange
    let openBraceIndex: Int
    let closeBraceIndex: Int
    let declarations: [CSSDeclaration]

    var displayPath: String {
        let path = parentAtRules + [selector]
        return path.joined(separator: " > ")
    }

    func declaration(named name: String) -> CSSDeclaration? {
        declarations.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

enum CSSEngine {
    private struct BlockInfo {
        let header: String
        let headerRange: NSRange
        let openBraceIndex: Int
        var closeBraceIndex: Int?
        let depth: Int
        let ancestorIndices: [Int]

        var isAtRule: Bool {
            header.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@")
        }
    }

    static func resolveRule(in text: String, at location: Int) -> CSSRuleContext? {
        let blocks = scanBlocks(in: text)
        let matchingBlocks = blocks.compactMap { block -> BlockInfo? in
            guard let closeBraceIndex = block.closeBraceIndex else {
                return nil
            }

            guard !block.isAtRule,
                  block.openBraceIndex < location,
                  location <= closeBraceIndex else {
                return nil
            }

            return block
        }

        guard let block = matchingBlocks.max(by: { $0.depth < $1.depth }) else {
            return nil
        }

        return makeRuleContext(from: block, in: text, blocks: blocks)
    }

    static func findRootRule(in text: String) -> CSSRuleContext? {
        let blocks = scanBlocks(in: text)
        guard let block = blocks.first(where: { !$0.isAtRule && $0.header.trimmingCharacters(in: .whitespacesAndNewlines) == ":root" }) else {
            return nil
        }

        return makeRuleContext(from: block, in: text, blocks: blocks)
    }

    static func createRootRule(in text: String) -> (text: String, rule: CSSRuleContext?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = trimmed.isEmpty ? "" : "\n\n"
        let updated = text + prefix + ":root {\n}\n"
        return (updated, findRootRule(in: updated))
    }

    static func upsertProperty(named name: String, value: String, in text: String, context: CSSRuleContext) -> String {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return removeProperty(named: name, in: text, context: context)
        }

        if let declaration = context.declaration(named: name) {
            let replacement = "\(declaration.indentation)\(name): \(value);"
            return replacing(range: declaration.range, in: text, with: replacement)
        }

        return insertingProperty(named: name, value: value, in: text, context: context)
    }

    static func removeProperty(named name: String, in text: String, context: CSSRuleContext) -> String {
        guard let declaration = context.declaration(named: name) else {
            return text
        }

        let characters = Array(text)
        let contentStart = context.openBraceIndex + 1
        let blockEnd = context.closeBraceIndex
        var start = declaration.range.location
        var end = declaration.range.location + declaration.range.length

        while start > contentStart, characters[start - 1] == " " || characters[start - 1] == "\t" {
            start -= 1
        }

        while end < blockEnd, characters[end] == " " || characters[end] == "\t" {
            end += 1
        }

        if end < blockEnd, characters[end] == "\n" || characters[end] == "\r" {
            end += 1
            if end < blockEnd, characters[end - 1] == "\r", characters[end] == "\n" {
                end += 1
            }
        } else if start > contentStart, characters[start - 1] == "\n" {
            start -= 1
        }

        return replacing(range: NSRange(location: start, length: max(0, end - start)), in: text, with: "")
    }

    static func parseMeasurement(_ value: String) -> (number: String, unit: String)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(-?(?:\d+(?:\.\d+)?|\.\d+))(px|rem|em|%|vh|vw|vmin|vmax|pt|fr|s|ms|deg)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range) else {
            return nil
        }

        let numberRange = Range(match.range(at: 1), in: trimmed)
        let unitRange = Range(match.range(at: 2), in: trimmed)
        let number = numberRange.map { String(trimmed[$0]) } ?? ""
        let unit = unitRange.map { String(trimmed[$0]) } ?? ""
        return (number, unit)
    }

    static func stringifyMeasurement(numberOrRaw: String, unit: String) -> String {
        let trimmed = numberOrRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        if Double(trimmed) != nil {
            return trimmed + unit
        }

        return trimmed
    }

    private static func makeRuleContext(from block: BlockInfo, in text: String, blocks: [BlockInfo]) -> CSSRuleContext? {
        guard let closeBraceIndex = block.closeBraceIndex else {
            return nil
        }

        let declarationsStart = block.openBraceIndex + 1
        guard declarationsStart <= closeBraceIndex else {
            return nil
        }

        let characters = Array(text)
        let content = String(characters[declarationsStart..<closeBraceIndex])
        let declarations = parseDeclarations(in: content, offset: declarationsStart)
        let parentAtRules = block.ancestorIndices.compactMap { ancestorIndex -> String? in
            let ancestor = blocks[ancestorIndex]
            return ancestor.isAtRule ? ancestor.header.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        }

        return CSSRuleContext(
            selector: block.header.trimmingCharacters(in: .whitespacesAndNewlines),
            parentAtRules: parentAtRules,
            headerRange: block.headerRange,
            blockRange: NSRange(location: block.headerRange.location, length: closeBraceIndex - block.headerRange.location + 1),
            openBraceIndex: block.openBraceIndex,
            closeBraceIndex: closeBraceIndex,
            declarations: declarations
        )
    }

    private static func scanBlocks(in text: String) -> [BlockInfo] {
        let characters = Array(text)
        var blocks: [BlockInfo] = []
        var stack: [Int] = []
        var segmentStartByDepth: [Int: Int] = [0: 0]
        var depth = 0
        var index = 0
        var inBlockComment = false
        var inLineComment = false
        var stringDelimiter: Character?

        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            if inBlockComment {
                if character == "*", next == "/" {
                    inBlockComment = false
                    index += 2
                    continue
                }

                index += 1
                continue
            }

            if inLineComment {
                if character == "\n" {
                    inLineComment = false
                }

                index += 1
                continue
            }

            if let delimiter = stringDelimiter {
                if character == "\\" {
                    index += 2
                    continue
                }

                if character == delimiter {
                    stringDelimiter = nil
                }

                index += 1
                continue
            }

            if character == "/", next == "*" {
                inBlockComment = true
                index += 2
                continue
            }

            if character == "/", next == "/" {
                inLineComment = true
                index += 2
                continue
            }

            if character == "\"" || character == "'" {
                stringDelimiter = character
                index += 1
                continue
            }

            if character == ";" {
                segmentStartByDepth[depth] = index + 1
                index += 1
                continue
            }

            if character == "{" {
                let headerStart = segmentStartByDepth[depth] ?? 0
                let headerEnd = index
                let header = String(characters[headerStart..<headerEnd])
                let block = BlockInfo(
                    header: header,
                    headerRange: NSRange(location: headerStart, length: headerEnd - headerStart),
                    openBraceIndex: index,
                    closeBraceIndex: nil,
                    depth: depth,
                    ancestorIndices: stack
                )
                blocks.append(block)
                let blockIndex = blocks.count - 1
                stack.append(blockIndex)
                depth += 1
                segmentStartByDepth[depth] = index + 1
                index += 1
                continue
            }

            if character == "}" {
                depth = max(depth - 1, 0)
                if let blockIndex = stack.popLast() {
                    blocks[blockIndex].closeBraceIndex = index
                }
                segmentStartByDepth[depth] = index + 1
                index += 1
                continue
            }

            index += 1
        }

        return blocks.compactMap { block in
            guard block.closeBraceIndex != nil else {
                return nil
            }

            return block
        }
    }

    private static func parseDeclarations(in content: String, offset: Int) -> [CSSDeclaration] {
        let characters = Array(content)
        var declarations: [CSSDeclaration] = []
        var segmentStart = 0
        var index = 0
        var inBlockComment = false
        var inLineComment = false
        var stringDelimiter: Character?
        var parenthesisDepth = 0

        while index <= characters.count {
            let isTerminator = index == characters.count
            let character = isTerminator ? ";" : characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            if !isTerminator {
                if inBlockComment {
                    if character == "*", next == "/" {
                        inBlockComment = false
                        index += 2
                        continue
                    }

                    index += 1
                    continue
                }

                if inLineComment {
                    if character == "\n" {
                        inLineComment = false
                    }

                    index += 1
                    continue
                }

                if let delimiter = stringDelimiter {
                    if character == "\\" {
                        index += 2
                        continue
                    }

                    if character == delimiter {
                        stringDelimiter = nil
                    }

                    index += 1
                    continue
                }

                if character == "/", next == "*" {
                    inBlockComment = true
                    index += 2
                    continue
                }

                if character == "/", next == "/" {
                    inLineComment = true
                    index += 2
                    continue
                }

                if character == "\"" || character == "'" {
                    stringDelimiter = character
                    index += 1
                    continue
                }

                if character == "(" {
                    parenthesisDepth += 1
                } else if character == ")" {
                    parenthesisDepth = max(parenthesisDepth - 1, 0)
                }
            }

            if isTerminator || (character == ";" && parenthesisDepth == 0) {
                let end = isTerminator ? index : index + 1
                let raw = String(characters[segmentStart..<end])
                if let declaration = makeDeclaration(from: raw, absoluteStart: offset + segmentStart) {
                    declarations.append(declaration)
                }
                segmentStart = end
            }

            index += 1
        }

        return declarations
    }

    private static func makeDeclaration(from raw: String, absoluteStart: Int) -> CSSDeclaration? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard let colonOffset = firstTopLevelColon(in: raw) else {
            return nil
        }

        let rawNSString = raw as NSString
        let name = rawNSString.substring(to: colonOffset).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return nil
        }

        var value = rawNSString.substring(from: colonOffset + 1)
        if value.hasSuffix(";") {
            value.removeLast()
        }

        let indentation = raw.prefix { $0 == " " || $0 == "\t" }

        return CSSDeclaration(
            name: name,
            value: value.trimmingCharacters(in: .whitespacesAndNewlines),
            range: NSRange(location: absoluteStart, length: rawNSString.length),
            indentation: String(indentation)
        )
    }

    private static func firstTopLevelColon(in text: String) -> Int? {
        let characters = Array(text)
        var parenthesisDepth = 0
        var stringDelimiter: Character?
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if let delimiter = stringDelimiter {
                if character == "\\" {
                    index += 2
                    continue
                }

                if character == delimiter {
                    stringDelimiter = nil
                }

                index += 1
                continue
            }

            if character == "\"" || character == "'" {
                stringDelimiter = character
                index += 1
                continue
            }

            if character == "(" {
                parenthesisDepth += 1
            } else if character == ")" {
                parenthesisDepth = max(parenthesisDepth - 1, 0)
            } else if character == ":", parenthesisDepth == 0 {
                return index
            }

            index += 1
        }

        return nil
    }

    private static func insertingProperty(named name: String, value: String, in text: String, context: CSSRuleContext) -> String {
        let characters = Array(text)
        let contentStart = context.openBraceIndex + 1
        var insertionPoint = context.closeBraceIndex

        while insertionPoint > contentStart, characters[insertionPoint - 1].isWhitespace {
            insertionPoint -= 1
        }

        let indentation = context.declarations.first?.indentation ?? inferredIndentation(in: text, context: context)
        let trailingWhitespace = String(characters[insertionPoint..<context.closeBraceIndex])
        let needsTrailingNewline = !trailingWhitespace.contains(where: { $0.isNewline })
        let addition = "\n\(indentation)\(name): \(value);" + (needsTrailingNewline ? "\n" : "")
        return replacing(range: NSRange(location: insertionPoint, length: 0), in: text, with: addition)
    }

    private static func inferredIndentation(in text: String, context: CSSRuleContext) -> String {
        let characters = Array(text)
        var lineStart = context.headerRange.location

        while lineStart > 0, characters[lineStart - 1] != "\n" {
            lineStart -= 1
        }

        let baseIndent = String(characters[lineStart..<context.headerRange.location].prefix { $0 == " " || $0 == "\t" })
        return baseIndent + "    "
    }

    private static func replacing(range: NSRange, in text: String, with replacement: String) -> String {
        guard let swiftRange = Range(range, in: text) else {
            return text
        }

        var updated = text
        updated.replaceSubrange(swiftRange, with: replacement)
        return updated
    }
}

private extension Character {
    var isWhitespace: Bool {
        unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
    }
}
