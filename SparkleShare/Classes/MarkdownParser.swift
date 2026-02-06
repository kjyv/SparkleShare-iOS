//
//  MarkdownParser.swift
//  SparkleShare
//
//  Swift wrapper around cmark-gfm C library for parsing markdown into an AST.
//

import Foundation

// MARK: - Node Location Tracking

/// Tracks the source location of a markdown node for inline editing
struct NodeLocation {
    let id: String
    let nodeType: String  // "paragraph", "heading", "listItem", "taskListItem", etc.
    let startLine: Int
    let endLine: Int
}

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

// MARK: - Markdown Parser

class MarkdownParser {

    // Counter for assigning indices to task list items during parsing
    private static var taskListCounter = 0
    // Counter for generating unique node IDs
    private static var nodeIdCounter = 0
    // Storage for node locations during parsing
    private static var nodeLocations: [String: (start: Int, end: Int)] = [:]
    // Original markdown (before preprocessing)
    private static var originalMarkdown: String = ""
    // Track last valid line number seen (for inferring positions when cmark returns 0)
    private static var lastSeenEndLine: Int = 0
    // Mapping from preprocessed line number to original line number
    private static var lineMapping: [Int: Int] = [:]

    /// Parse markdown and return both the AST and node location information
    static func parseWithLocations(_ markdown: String) -> MarkdownParseResult {
        // Reset counters for each parse
        taskListCounter = 0
        nodeIdCounter = 0
        nodeLocations = [:]
        originalMarkdown = markdown
        lastSeenEndLine = 0
        lineMapping = [:]

        // Preprocess markdown for nested lists (this also builds lineMapping)
        let preprocessed = preprocessMarkdownForNestedLists(markdown)

        // Register GFM extensions
        cmark_gfm_core_extensions_ensure_registered()

        // Create parser
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else {
            let fallbackId = generateNodeId()
            return MarkdownParseResult(
                ast: .document(id: fallbackId, children: [.paragraph(id: generateNodeId(), children: [.text(markdown)])]),
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
            let fallbackId = generateNodeId()
            return MarkdownParseResult(
                ast: .document(id: fallbackId, children: [.paragraph(id: generateNodeId(), children: [.text(markdown)])]),
                nodeLocations: [:],
                originalMarkdown: markdown
            )
        }

        // Convert to Swift AST
        let ast = convertNode(document)

        // Cleanup
        cmark_node_free(document)
        cmark_parser_free(parser)

        return MarkdownParseResult(
            ast: ast,
            nodeLocations: nodeLocations,
            originalMarkdown: markdown
        )
    }

    /// Legacy parse function for backwards compatibility
    static func parse(_ markdown: String) -> MarkdownNode {
        return parseWithLocations(markdown).ast
    }

    // MARK: - Private

    private static func generateNodeId() -> String {
        nodeIdCounter += 1
        return "node_\(nodeIdCounter)"
    }

    /// Infer the next content line by advancing past empty lines from lastSeenEndLine
    private static func inferNextContentLine() -> Int {
        var line = lastSeenEndLine + 1
        let origLines = originalMarkdown.components(separatedBy: "\n")
        while line <= origLines.count,
              origLines[line - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            line += 1
        }
        return line
    }

    private static func convertNode(_ node: UnsafeMutablePointer<cmark_node>) -> MarkdownNode {
        let nodeType = cmark_node_get_type(node)
        let nodeId = generateNodeId()

        // Get line positions from cmark
        let startLine = Int(cmark_node_get_start_line(node))
        let endLine = Int(cmark_node_get_end_line(node))

        // Map preprocessed line numbers to original line numbers
        let origStartLine = mapToOriginalLine(startLine)
        let origEndLine = mapToOriginalLine(endLine)

        switch nodeType {
        case CMARK_NODE_DOCUMENT:
            // Track document location
            if startLine > 0 && endLine > 0 {
                nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                lastSeenEndLine = max(lastSeenEndLine, origEndLine)
            }
            return .document(id: nodeId, children: convertChildren(node))

        case CMARK_NODE_HEADING:
            let level = Int(cmark_node_get_heading_level(node))
            // Track heading location for editing
            if startLine > 0 && endLine > 0 {
                nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                lastSeenEndLine = origEndLine
            }
            return .heading(id: nodeId, level: level, children: convertChildren(node))

        case CMARK_NODE_PARAGRAPH:
            // Track paragraph location for editing
            if startLine > 0 && endLine > 0 {
                nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                lastSeenEndLine = origEndLine
            } else {
                // cmark returned 0-0, try to infer position from text content
                let textContent = extractTextFromNode(node)

                if textContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Empty paragraph (e.g., inside a list item with no text after checkbox)
                    // Share the parent's position since it's on the same line
                    nodeLocations[nodeId] = (start: lastSeenEndLine, end: lastSeenEndLine)
                } else {
                    let lineCount = max(1, textContent.components(separatedBy: "\n").count)
                    let origLines = originalMarkdown.components(separatedBy: "\n")
                    var inferredStart: Int

                    // Check if the parent line is a list item — if so, the paragraph
                    // is its child and shares the same line
                    let parentIsListItem: Bool
                    if lastSeenEndLine > 0 && lastSeenEndLine <= origLines.count {
                        let trimmedLine = origLines[lastSeenEndLine - 1]
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
                        inferredStart = lastSeenEndLine
                    } else {
                        inferredStart = lastSeenEndLine + 1
                        // Skip empty lines to find actual content start
                        while inferredStart <= origLines.count,
                              origLines[inferredStart - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                            inferredStart += 1
                        }
                    }

                    let inferredEnd = inferredStart + lineCount - 1
                    nodeLocations[nodeId] = (start: inferredStart, end: inferredEnd)
                    lastSeenEndLine = inferredEnd
                }
            }
            return .paragraph(id: nodeId, children: convertChildren(node))

        case CMARK_NODE_BLOCK_QUOTE:
            // Track blockquote location
            if startLine > 0 && endLine > 0 {
                nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                lastSeenEndLine = origEndLine
            }
            return .blockquote(id: nodeId, children: convertChildren(node))

        case CMARK_NODE_LIST:
            let ordered = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
            let start = Int(cmark_node_get_list_start(node))
            let tight = cmark_node_get_list_tight(node) != 0
            // Track list location
            if startLine > 0 && endLine > 0 {
                nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                lastSeenEndLine = origEndLine
            }
            return .list(id: nodeId, ordered: ordered, start: start, tight: tight, children: convertChildren(node))

        case CMARK_NODE_ITEM:
            // Check if this is a task list item
            // The tasklist extension marks items with type string "tasklist" and removes the [x]/[ ] syntax
            let typeString = cmark_node_get_type_string(node).map { String(cString: $0) } ?? ""

            if typeString == "tasklist" {
                // This is a task list item - get the checked state from the extension
                let checked = cmark_gfm_extensions_get_tasklist_item_checked(node)
                let index = taskListCounter
                taskListCounter += 1
                // Track task list item location
                if startLine > 0 && endLine > 0 {
                    nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    lastSeenEndLine = origEndLine
                } else {
                    // Infer position for task list items with 0-0
                    let inferredLine = inferNextContentLine()
                    nodeLocations[nodeId] = (start: inferredLine, end: inferredLine)
                    lastSeenEndLine = inferredLine
                }
                let taskChildren = convertChildren(node)
                if taskChildren.isEmpty {
                    // cmark doesn't create children for empty task list items — synthesize an empty paragraph
                    let syntheticParaId = generateNodeId()
                    let loc = nodeLocations[nodeId] ?? (start: lastSeenEndLine, end: lastSeenEndLine)
                    nodeLocations[syntheticParaId] = loc
                    return .taskListItem(id: nodeId, index: index, checked: checked,
                                         children: [.paragraph(id: syntheticParaId, children: [])])
                }
                return .taskListItem(id: nodeId, index: index, checked: checked, children: taskChildren)
            }

            // Track list item location
            if startLine > 0 && endLine > 0 {
                nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                lastSeenEndLine = origEndLine
            } else {
                // Infer position for list items with 0-0
                let inferredLine = inferNextContentLine()
                nodeLocations[nodeId] = (start: inferredLine, end: inferredLine)
                lastSeenEndLine = inferredLine
            }
            let itemChildren = convertChildren(node)
            if itemChildren.isEmpty {
                // cmark doesn't create children for empty list items — synthesize an empty paragraph
                let syntheticParaId = generateNodeId()
                let loc = nodeLocations[nodeId] ?? (start: lastSeenEndLine, end: lastSeenEndLine)
                nodeLocations[syntheticParaId] = loc
                return .listItem(id: nodeId, children: [.paragraph(id: syntheticParaId, children: [])])
            }
            return .listItem(id: nodeId, children: itemChildren)

        case CMARK_NODE_CODE_BLOCK:
            let info = cmark_node_get_fence_info(node).flatMap { String(cString: $0) }
            let literal = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
            // Track code block location
            if startLine > 0 && endLine > 0 {
                nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                lastSeenEndLine = origEndLine
            }
            return .codeBlock(id: nodeId, info: info?.isEmpty == true ? nil : info, literal: literal)

        case CMARK_NODE_HTML_BLOCK:
            let literal = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
            // Track HTML block location
            if startLine > 0 && endLine > 0 {
                nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                lastSeenEndLine = origEndLine
            }
            return .htmlBlock(id: nodeId, literal: literal)

        case CMARK_NODE_THEMATIC_BREAK:
            // Track thematic break location
            if startLine > 0 && endLine > 0 {
                nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                lastSeenEndLine = origEndLine
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
            return .emphasis(children: convertChildren(node))

        case CMARK_NODE_STRONG:
            return .strong(children: convertChildren(node))

        case CMARK_NODE_LINK:
            let url = cmark_node_get_url(node).map { String(cString: $0) } ?? ""
            let title = cmark_node_get_title(node).flatMap { String(cString: $0) }
            return .link(url: url, title: title?.isEmpty == true ? nil : title, children: convertChildren(node))

        case CMARK_NODE_IMAGE:
            let url = cmark_node_get_url(node).map { String(cString: $0) } ?? ""
            let title = cmark_node_get_title(node).flatMap { String(cString: $0) }
            // Get alt text from children
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
                return .strikethrough(children: convertChildren(node))

            case "table":
                // Parse table alignments
                var alignments: [TableAlignment] = []
                if let firstRow = cmark_node_first_child(node) {
                    var cell = cmark_node_first_child(firstRow)
                    while let c = cell {
                        let cellTypeString = cmark_node_get_type_string(c).map { String(cString: $0) } ?? ""
                        if cellTypeString == "table_cell" {
                            // cmark-gfm doesn't expose alignment directly, default to none
                            alignments.append(.none)
                        }
                        cell = cmark_node_next(c)
                    }
                }
                // Track table location
                if startLine > 0 && endLine > 0 {
                    nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    lastSeenEndLine = origEndLine
                }
                return .table(id: nodeId, alignments: alignments, children: convertChildren(node))

            case "table_row":
                // Track table row location
                if startLine > 0 && endLine > 0 {
                    nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    lastSeenEndLine = origEndLine
                }
                return .tableRow(id: nodeId, children: convertChildren(node))

            case "table_cell":
                // Track table cell location
                if startLine > 0 && endLine > 0 {
                    nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    lastSeenEndLine = origEndLine
                }
                return .tableCell(id: nodeId, children: convertChildren(node))

            case "table_header":
                // Track table header location
                if startLine > 0 && endLine > 0 {
                    nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    lastSeenEndLine = origEndLine
                }
                return .tableRow(id: nodeId, children: convertChildren(node))

            case "tasklist":
                // Fallback for tasklist extension node type
                if startLine > 0 && endLine > 0 {
                    nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    lastSeenEndLine = origEndLine
                }
                return .listItem(id: nodeId, children: convertChildren(node))

            default:
                // Unknown node type, try to convert children
                let children = convertChildren(node)
                if children.isEmpty {
                    return .text("")
                }
                // Track unknown block location
                if startLine > 0 && endLine > 0 {
                    nodeLocations[nodeId] = (start: origStartLine, end: origEndLine)
                    lastSeenEndLine = origEndLine
                }
                return .paragraph(id: nodeId, children: children)
            }
        }
    }

    private static func convertChildren(_ node: UnsafeMutablePointer<cmark_node>) -> [MarkdownNode] {
        var children: [MarkdownNode] = []
        var child = cmark_node_first_child(node)
        while let c = child {
            children.append(convertNode(c))
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
                // Recurse into other nodes
                text += extractTextFromNode(c)
            }
            child = cmark_node_next(c)
        }
        return text
    }

    // MARK: - Preprocessing

    /// Map a preprocessed line number to the original line number
    private static func mapToOriginalLine(_ preprocessedLine: Int) -> Int {
        return lineMapping[preprocessedLine] ?? preprocessedLine
    }

    /// Preprocess markdown to fix nested list parsing for cmark-gfm
    /// Also builds lineMapping to map preprocessed line numbers back to original
    private static func preprocessMarkdownForNestedLists(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var processedLines: [String] = []
        var prevIndentLevel = -1

        // Track mapping: processedLineNumber (1-based) -> originalLineNumber (1-based)
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
                    // Adding an extra empty line - map it to the current original line
                    processedLines.append("")
                    lineMapping[processedLines.count] = currentOriginalLine
                }
                prevIndentLevel = indentLevel

                var newLine = ""
                for _ in 0..<indentLevel {
                    newLine += "  "
                }
                newLine += trimmedLine
                processedLines.append(newLine)
                lineMapping[processedLines.count] = currentOriginalLine
            } else if trimmedLine.trimmingCharacters(in: .whitespaces).isEmpty {
                prevIndentLevel = -1
                processedLines.append(line)
                lineMapping[processedLines.count] = currentOriginalLine
            } else {
                var newLine = ""
                for _ in 0..<indentLevel {
                    newLine += "  "
                }
                newLine += trimmedLine
                processedLines.append(newLine)
                lineMapping[processedLines.count] = currentOriginalLine
            }
        }

        return processedLines.joined(separator: "\n")
    }
}
