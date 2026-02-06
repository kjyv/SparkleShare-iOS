//
//  MarkdownParser.swift
//  SparkleShare
//
//  Swift wrapper around cmark-gfm C library for parsing markdown into an AST.
//

import Foundation

// MARK: - Parse Result

/// Result of parsing markdown, including the AST and node locations
struct MarkdownParseResult {
    let ast: MarkdownNode
    let nodeLocations: [String: (start: Int, end: Int)]
    let originalMarkdown: String
}

// MARK: - AST Node Types

enum MarkdownNode {
    case document(id: String, children: [MarkdownNode])
    case heading(id: String, level: Int, children: [MarkdownNode])
    case paragraph(id: String, children: [MarkdownNode])
    case blockquote(id: String, children: [MarkdownNode])
    case list(id: String, ordered: Bool, start: Int, tight: Bool, children: [MarkdownNode])
    case listItem(id: String, children: [MarkdownNode])
    case taskListItem(id: String, index: Int, checked: Bool, children: [MarkdownNode])
    case codeBlock(id: String, info: String?, literal: String)
    case htmlBlock(id: String, literal: String)
    case thematicBreak(id: String)
    case table(id: String, alignments: [TableAlignment], children: [MarkdownNode])
    case tableRow(id: String, children: [MarkdownNode])
    case tableCell(id: String, children: [MarkdownNode])
    case text(String)
    case softBreak
    case lineBreak
    case code(String)
    case htmlInline(String)
    case emphasis(children: [MarkdownNode])
    case strong(children: [MarkdownNode])
    case strikethrough(children: [MarkdownNode])
    case link(url: String, title: String?, children: [MarkdownNode])
    case image(url: String, title: String?, alt: String)
}

enum TableAlignment {
    case none
    case left
    case center
    case right
}

// MARK: - Parsing Context

/// Holds all mutable state for a single parse operation (thread-safe by construction)
private class ParsingContext {
    var taskListCounter = 0
    var nodeIdCounter = 0
    var nodeLocations: [String: (start: Int, end: Int)] = [:]
    var originalMarkdown: String = ""
    var lastSeenEndLine: Int = 0
    var lineMapping: [Int: Int] = [:]

    func generateNodeId() -> String {
        nodeIdCounter += 1
        return "node_\(nodeIdCounter)"
    }

    func mapToOriginalLine(_ preprocessedLine: Int) -> Int {
        return lineMapping[preprocessedLine] ?? preprocessedLine
    }

    /// Infer the next content line by advancing past empty lines from lastSeenEndLine
    func inferNextContentLine() -> Int {
        var line = lastSeenEndLine + 1
        let origLines = originalMarkdown.components(separatedBy: "\n")
        while line <= origLines.count,
              origLines[line - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            line += 1
        }
        return line
    }
}

// MARK: - Markdown Parser

class MarkdownParser {

    /// Parse markdown and return both the AST and node location information
    static func parseWithLocations(_ markdown: String) -> MarkdownParseResult {
        let ctx = ParsingContext()
        ctx.originalMarkdown = markdown

        // Preprocess markdown for nested lists (this also builds lineMapping)
        let preprocessed = preprocessMarkdownForNestedLists(markdown, ctx: ctx)

        // Register GFM extensions
        cmark_gfm_core_extensions_ensure_registered()

        // Create parser
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else {
            let fallbackId = ctx.generateNodeId()
            return MarkdownParseResult(
                ast: .document(id: fallbackId, children: [.paragraph(id: ctx.generateNodeId(), children: [.text(markdown)])]),
                nodeLocations: [:],
                originalMarkdown: markdown
            )
        }

        // Attach GFM extensions
        if let tableExt = cmark_find_syntax_extension("table") {
            cmark_parser_attach_syntax_extension(parser, tableExt)
        }
        if let strikethroughExt = cmark_find_syntax_extension("strikethrough") {
            cmark_parser_attach_syntax_extension(parser, strikethroughExt)
        }
        if let tasklistExt = cmark_find_syntax_extension("tasklist") {
            cmark_parser_attach_syntax_extension(parser, tasklistExt)
        }
        if let autolinkExt = cmark_find_syntax_extension("autolink") {
            cmark_parser_attach_syntax_extension(parser, autolinkExt)
        }

        // Parse
        cmark_parser_feed(parser, preprocessed, preprocessed.utf8.count)
        guard let document = cmark_parser_finish(parser) else {
            cmark_parser_free(parser)
            let fallbackId = ctx.generateNodeId()
            return MarkdownParseResult(
                ast: .document(id: fallbackId, children: [.paragraph(id: ctx.generateNodeId(), children: [.text(markdown)])]),
                nodeLocations: [:],
                originalMarkdown: markdown
            )
        }

        // Convert to Swift AST
        let ast = convertNode(document, ctx: ctx)

        // Cleanup
        cmark_node_free(document)
        cmark_parser_free(parser)

        return MarkdownParseResult(
            ast: ast,
            nodeLocations: ctx.nodeLocations,
            originalMarkdown: markdown
        )
    }

    /// Legacy parse function for backwards compatibility
    static func parse(_ markdown: String) -> MarkdownNode {
        return parseWithLocations(markdown).ast
    }

    // MARK: - Private

    private static func convertNode(_ node: UnsafeMutablePointer<cmark_node>, ctx: ParsingContext) -> MarkdownNode {
        let nodeType = cmark_node_get_type(node)
        let nodeId = ctx.generateNodeId()

        // Get line positions from cmark
        let startLine = Int(cmark_node_get_start_line(node))
        let endLine = Int(cmark_node_get_end_line(node))

        // Map preprocessed line numbers to original line numbers
        let origStartLine = ctx.mapToOriginalLine(startLine)
        let origEndLine = ctx.mapToOriginalLine(endLine)

        switch nodeType {
        case CMARK_NODE_DOCUMENT:
            if startLine > 0 && endLine > 0 {
                ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                ctx.lastSeenEndLine = max(ctx.lastSeenEndLine, origEndLine)
            }
            return .document(id: nodeId, children: convertChildren(node, ctx: ctx))

        case CMARK_NODE_HEADING:
            let level = Int(cmark_node_get_heading_level(node))
            if startLine > 0 && endLine > 0 {
                ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                ctx.lastSeenEndLine = origEndLine
            }
            return .heading(id: nodeId, level: level, children: convertChildren(node, ctx: ctx))

        case CMARK_NODE_PARAGRAPH:
            if startLine > 0 && endLine > 0 {
                ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                ctx.lastSeenEndLine = origEndLine
            } else {
                // cmark returned 0-0, try to infer position from text content
                let textContent = extractTextFromNode(node)

                if textContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Empty paragraph (e.g., inside a list item with no text after checkbox)
                    ctx.nodeLocations[nodeId] = (start: ctx.lastSeenEndLine, end: ctx.lastSeenEndLine)
                } else {
                    let lineCount = max(1, textContent.components(separatedBy: "\n").count)
                    let origLines = ctx.originalMarkdown.components(separatedBy: "\n")
                    var inferredStart: Int

                    // Check if the parent line is a list item — if so, the paragraph
                    // is its child and shares the same line
                    let parentIsListItem: Bool
                    if ctx.lastSeenEndLine > 0 && ctx.lastSeenEndLine <= origLines.count {
                        let trimmedLine = origLines[ctx.lastSeenEndLine - 1]
                            .trimmingCharacters(in: .whitespaces)
                        parentIsListItem = trimmedLine.hasPrefix("- ") ||
                            trimmedLine.hasPrefix("* ") ||
                            trimmedLine.hasPrefix("+ ") ||
                            trimmedLine.hasPrefix("- [") ||
                            trimmedLine.range(of: "^\\d+\\. ", options: .regularExpression) != nil
                    } else {
                        parentIsListItem = false
                    }

                    if parentIsListItem {
                        inferredStart = ctx.lastSeenEndLine
                    } else {
                        inferredStart = ctx.lastSeenEndLine + 1
                        while inferredStart <= origLines.count,
                              origLines[inferredStart - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                            inferredStart += 1
                        }
                    }

                    let inferredEnd = inferredStart + lineCount - 1
                    ctx.nodeLocations[nodeId] = (start: inferredStart, end: inferredEnd)
                    ctx.lastSeenEndLine = inferredEnd
                }
            }
            return .paragraph(id: nodeId, children: convertChildren(node, ctx: ctx))

        case CMARK_NODE_BLOCK_QUOTE:
            if startLine > 0 && endLine > 0 {
                ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                ctx.lastSeenEndLine = origEndLine
            }
            return .blockquote(id: nodeId, children: convertChildren(node, ctx: ctx))

        case CMARK_NODE_LIST:
            let ordered = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
            let start = Int(cmark_node_get_list_start(node))
            let tight = cmark_node_get_list_tight(node) != 0
            if startLine > 0 && endLine > 0 {
                ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                ctx.lastSeenEndLine = origEndLine
            }
            return .list(id: nodeId, ordered: ordered, start: start, tight: tight, children: convertChildren(node, ctx: ctx))

        case CMARK_NODE_ITEM:
            let typeString = cmark_node_get_type_string(node).map { String(cString: $0) } ?? ""

            if typeString == "tasklist" {
                let checked = cmark_gfm_extensions_get_tasklist_item_checked(node)
                let index = ctx.taskListCounter
                ctx.taskListCounter += 1
                if startLine > 0 && endLine > 0 {
                    ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    ctx.lastSeenEndLine = origEndLine
                } else {
                    let inferredLine = ctx.inferNextContentLine()
                    ctx.nodeLocations[nodeId] = (start: inferredLine, end: inferredLine)
                    ctx.lastSeenEndLine = inferredLine
                }
                let taskChildren = convertChildren(node, ctx: ctx)
                if taskChildren.isEmpty {
                    let syntheticParaId = ctx.generateNodeId()
                    let loc = ctx.nodeLocations[nodeId] ?? (start: ctx.lastSeenEndLine, end: ctx.lastSeenEndLine)
                    ctx.nodeLocations[syntheticParaId] = loc
                    return .taskListItem(id: nodeId, index: index, checked: checked,
                                         children: [.paragraph(id: syntheticParaId, children: [])])
                }
                return .taskListItem(id: nodeId, index: index, checked: checked, children: taskChildren)
            }

            if startLine > 0 && endLine > 0 {
                ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                ctx.lastSeenEndLine = origEndLine
            } else {
                let inferredLine = ctx.inferNextContentLine()
                ctx.nodeLocations[nodeId] = (start: inferredLine, end: inferredLine)
                ctx.lastSeenEndLine = inferredLine
            }
            let itemChildren = convertChildren(node, ctx: ctx)
            if itemChildren.isEmpty {
                let syntheticParaId = ctx.generateNodeId()
                let loc = ctx.nodeLocations[nodeId] ?? (start: ctx.lastSeenEndLine, end: ctx.lastSeenEndLine)
                ctx.nodeLocations[syntheticParaId] = loc
                return .listItem(id: nodeId, children: [.paragraph(id: syntheticParaId, children: [])])
            }
            return .listItem(id: nodeId, children: itemChildren)

        case CMARK_NODE_CODE_BLOCK:
            let info = cmark_node_get_fence_info(node).flatMap { String(cString: $0) }
            let literal = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
            if startLine > 0 && endLine > 0 {
                ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                ctx.lastSeenEndLine = origEndLine
            }
            return .codeBlock(id: nodeId, info: info?.isEmpty == true ? nil : info, literal: literal)

        case CMARK_NODE_HTML_BLOCK:
            let literal = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
            if startLine > 0 && endLine > 0 {
                ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                ctx.lastSeenEndLine = origEndLine
            }
            return .htmlBlock(id: nodeId, literal: literal)

        case CMARK_NODE_THEMATIC_BREAK:
            if startLine > 0 && endLine > 0 {
                ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                ctx.lastSeenEndLine = origEndLine
            }
            return .thematicBreak(id: nodeId)

        case CMARK_NODE_TEXT:
            let literal = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
            return .text(literal)

        case CMARK_NODE_SOFTBREAK:
            return .softBreak

        case CMARK_NODE_LINEBREAK:
            return .lineBreak

        case CMARK_NODE_CODE:
            let literal = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
            return .code(literal)

        case CMARK_NODE_HTML_INLINE:
            let literal = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
            return .htmlInline(literal)

        case CMARK_NODE_EMPH:
            return .emphasis(children: convertChildren(node, ctx: ctx))

        case CMARK_NODE_STRONG:
            return .strong(children: convertChildren(node, ctx: ctx))

        case CMARK_NODE_LINK:
            let url = cmark_node_get_url(node).map { String(cString: $0) } ?? ""
            let title = cmark_node_get_title(node).flatMap { String(cString: $0) }
            return .link(url: url, title: title?.isEmpty == true ? nil : title, children: convertChildren(node, ctx: ctx))

        case CMARK_NODE_IMAGE:
            let url = cmark_node_get_url(node).map { String(cString: $0) } ?? ""
            let title = cmark_node_get_title(node).flatMap { String(cString: $0) }
            var alt = ""
            var child = cmark_node_first_child(node)
            while let c = child {
                if cmark_node_get_type(c) == CMARK_NODE_TEXT,
                   let literal = cmark_node_get_literal(c) {
                    alt += String(cString: literal)
                }
                child = cmark_node_next(c)
            }
            return .image(url: url, title: title?.isEmpty == true ? nil : title, alt: alt)

        default:
            // Handle extension node types
            let typeString = cmark_node_get_type_string(node).map { String(cString: $0) } ?? ""

            switch typeString {
            case "strikethrough":
                return .strikethrough(children: convertChildren(node, ctx: ctx))

            case "table":
                var alignments: [TableAlignment] = []
                if let firstRow = cmark_node_first_child(node) {
                    var cell = cmark_node_first_child(firstRow)
                    while let c = cell {
                        let cellTypeString = cmark_node_get_type_string(c).map { String(cString: $0) } ?? ""
                        if cellTypeString == "table_cell" {
                            alignments.append(.none)
                        }
                        cell = cmark_node_next(c)
                    }
                }
                if startLine > 0 && endLine > 0 {
                    ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    ctx.lastSeenEndLine = origEndLine
                }
                return .table(id: nodeId, alignments: alignments, children: convertChildren(node, ctx: ctx))

            case "table_row":
                if startLine > 0 && endLine > 0 {
                    ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    ctx.lastSeenEndLine = origEndLine
                }
                return .tableRow(id: nodeId, children: convertChildren(node, ctx: ctx))

            case "table_cell":
                if startLine > 0 && endLine > 0 {
                    ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    ctx.lastSeenEndLine = origEndLine
                }
                return .tableCell(id: nodeId, children: convertChildren(node, ctx: ctx))

            case "table_header":
                if startLine > 0 && endLine > 0 {
                    ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    ctx.lastSeenEndLine = origEndLine
                }
                return .tableRow(id: nodeId, children: convertChildren(node, ctx: ctx))

            case "tasklist":
                if startLine > 0 && endLine > 0 {
                    ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    ctx.lastSeenEndLine = origEndLine
                }
                return .listItem(id: nodeId, children: convertChildren(node, ctx: ctx))

            default:
                let children = convertChildren(node, ctx: ctx)
                if children.isEmpty {
                    return .text("")
                }
                if startLine > 0 && endLine > 0 {
                    ctx.nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    ctx.lastSeenEndLine = origEndLine
                }
                return .paragraph(id: nodeId, children: children)
            }
        }
    }

    private static func convertChildren(_ node: UnsafeMutablePointer<cmark_node>, ctx: ParsingContext) -> [MarkdownNode] {
        var children: [MarkdownNode] = []
        var child = cmark_node_first_child(node)
        while let c = child {
            children.append(convertNode(c, ctx: ctx))
            child = cmark_node_next(c)
        }
        return children
    }

    /// Extract plain text content from a cmark node (for inferring line count)
    private static func extractTextFromNode(_ node: UnsafeMutablePointer<cmark_node>) -> String {
        var text = ""
        var child = cmark_node_first_child(node)
        while let c = child {
            let childType = cmark_node_get_type(c)
            if childType == CMARK_NODE_TEXT {
                if let literal = cmark_node_get_literal(c) {
                    text += String(cString: literal)
                }
            } else if childType == CMARK_NODE_SOFTBREAK {
                text += "\n"
            } else if childType == CMARK_NODE_LINEBREAK {
                text += "\n"
            } else {
                text += extractTextFromNode(c)
            }
            child = cmark_node_next(c)
        }
        return text
    }

    // MARK: - Preprocessing

    /// Preprocess markdown to fix nested list parsing for cmark-gfm
    /// Also builds lineMapping to map preprocessed line numbers back to original
    private static func preprocessMarkdownForNestedLists(_ markdown: String, ctx: ParsingContext) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var processedLines: [String] = []
        var prevIndentLevel = -1
        var currentOriginalLine = 0

        for line in lines {
            currentOriginalLine += 1

            var charIndex = 0
            var indentLevel = 0
            var spaceCount = 0

            while charIndex < line.count {
                let index = line.index(line.startIndex, offsetBy: charIndex)
                let c = line[index]
                if c == "\t" {
                    indentLevel += (spaceCount + 1) / 3
                    spaceCount = 0
                    indentLevel += 1
                    charIndex += 1
                } else if c == " " {
                    spaceCount += 1
                    charIndex += 1
                } else {
                    break
                }
            }
            indentLevel += (spaceCount + 1) / 3

            // Only strip leading whitespace — preserve trailing whitespace so that
            // empty numbered list items like "4. " stay valid for cmark (needs trailing space).
            let trimmedLine = String(line.drop(while: { $0 == " " || $0 == "\t" }))

            let isNumberedListItem: Bool = {
                let digits = trimmedLine.prefix(while: { $0.isNumber })
                return !digits.isEmpty && trimmedLine.dropFirst(digits.count).hasPrefix(". ")
            }()
            let isListItem = trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") ||
                             trimmedLine.hasPrefix("+ ") || trimmedLine.hasPrefix("- [") ||
                             isNumberedListItem

            if isListItem {
                if indentLevel > prevIndentLevel && prevIndentLevel >= 0 {
                    processedLines.append("")
                    ctx.lineMapping[processedLines.count] = currentOriginalLine
                }
                prevIndentLevel = indentLevel

                var newLine = ""
                for _ in 0..<indentLevel {
                    newLine += "  "
                }
                newLine += trimmedLine
                processedLines.append(newLine)
                ctx.lineMapping[processedLines.count] = currentOriginalLine
            } else if trimmedLine.trimmingCharacters(in: .whitespaces).isEmpty {
                prevIndentLevel = -1
                processedLines.append(line)
                ctx.lineMapping[processedLines.count] = currentOriginalLine
            } else {
                var newLine = ""
                for _ in 0..<indentLevel {
                    newLine += "  "
                }
                newLine += trimmedLine
                processedLines.append(newLine)
                ctx.lineMapping[processedLines.count] = currentOriginalLine
            }
        }

        return processedLines.joined(separator: "\n")
    }
}
