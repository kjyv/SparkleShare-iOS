//
//  MarkdownParser.swift
//  SparkleShare
//
//  Swift wrapper around cmark-gfm C library for parsing markdown into an AST.
//

import Foundation

// MARK: - AST Node Types

enum MarkdownNode {
    case document(children: [MarkdownNode])
    case heading(level: Int, children: [MarkdownNode])
    case paragraph(children: [MarkdownNode])
    case blockquote(children: [MarkdownNode])
    case list(ordered: Bool, start: Int, tight: Bool, children: [MarkdownNode])
    case listItem(children: [MarkdownNode])
    case taskListItem(index: Int, checked: Bool, children: [MarkdownNode])
    case codeBlock(info: String?, literal: String)
    case htmlBlock(literal: String)
    case thematicBreak
    case table(alignments: [TableAlignment], children: [MarkdownNode])
    case tableRow(children: [MarkdownNode])
    case tableCell(children: [MarkdownNode])
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

    static func parse(_ markdown: String) -> MarkdownNode {
        // Reset counter for each parse
        taskListCounter = 0

        // Preprocess markdown for nested lists
        let preprocessed = preprocessMarkdownForNestedLists(markdown)

        // Register GFM extensions
        cmark_gfm_core_extensions_ensure_registered()

        // Create parser
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else {
            return .document(children: [.paragraph(children: [.text(markdown)])])
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
            return .document(children: [.paragraph(children: [.text(markdown)])])
        }

        // Convert to Swift AST
        let result = convertNode(document)

        // Cleanup
        cmark_node_free(document)
        cmark_parser_free(parser)

        return result
    }

    // MARK: - Private

    private static func convertNode(_ node: UnsafeMutablePointer<cmark_node>) -> MarkdownNode {
        let nodeType = cmark_node_get_type(node)

        switch nodeType {
        case CMARK_NODE_DOCUMENT:
            return .document(children: convertChildren(node))

        case CMARK_NODE_HEADING:
            let level = Int(cmark_node_get_heading_level(node))
            return .heading(level: level, children: convertChildren(node))

        case CMARK_NODE_PARAGRAPH:
            return .paragraph(children: convertChildren(node))

        case CMARK_NODE_BLOCK_QUOTE:
            return .blockquote(children: convertChildren(node))

        case CMARK_NODE_LIST:
            let ordered = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
            let start = Int(cmark_node_get_list_start(node))
            let tight = cmark_node_get_list_tight(node) != 0
            return .list(ordered: ordered, start: start, tight: tight, children: convertChildren(node))

        case CMARK_NODE_ITEM:
            // Check if this is a task list item
            // The tasklist extension marks items with type string "tasklist" and removes the [x]/[ ] syntax
            let typeString = cmark_node_get_type_string(node).map { String(cString: $0) } ?? ""

            if typeString == "tasklist" {
                // This is a task list item - get the checked state from the extension
                let checked = cmark_gfm_extensions_get_tasklist_item_checked(node)
                let index = taskListCounter
                taskListCounter += 1
                return .taskListItem(index: index, checked: checked, children: convertChildren(node))
            }

            return .listItem(children: convertChildren(node))

        case CMARK_NODE_CODE_BLOCK:
            let info = cmark_node_get_fence_info(node).flatMap { String(cString: $0) }
            let literal = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
            return .codeBlock(info: info?.isEmpty == true ? nil : info, literal: literal)

        case CMARK_NODE_HTML_BLOCK:
            let literal = cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
            return .htmlBlock(literal: literal)

        case CMARK_NODE_THEMATIC_BREAK:
            return .thematicBreak

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
                return .table(alignments: alignments, children: convertChildren(node))

            case "table_row":
                return .tableRow(children: convertChildren(node))

            case "table_cell":
                return .tableCell(children: convertChildren(node))

            case "table_header":
                return .tableRow(children: convertChildren(node))

            case "tasklist":
                // Fallback for tasklist extension node type
                return .listItem(children: convertChildren(node))

            default:
                // Unknown node type, try to convert children
                let children = convertChildren(node)
                if children.isEmpty {
                    return .text("")
                }
                return .paragraph(children: children)
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

    // MARK: - Preprocessing

    /// Preprocess markdown to fix nested list parsing for cmark-gfm
    private static func preprocessMarkdownForNestedLists(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var processedLines: [String] = []
        var prevIndentLevel = -1

        for line in lines {
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

            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            let isListItem = trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") ||
                             trimmedLine.hasPrefix("+ ") || trimmedLine.hasPrefix("- [")

            if isListItem {
                if indentLevel > prevIndentLevel && prevIndentLevel >= 0 {
                    processedLines.append("")
                }
                prevIndentLevel = indentLevel

                var newLine = ""
                for _ in 0..<indentLevel {
                    newLine += "  "
                }
                newLine += trimmedLine
                processedLines.append(newLine)
            } else if trimmedLine.isEmpty {
                prevIndentLevel = -1
                processedLines.append(line)
            } else {
                var newLine = ""
                for _ in 0..<indentLevel {
                    newLine += "  "
                }
                newLine += trimmedLine
                processedLines.append(newLine)
            }
        }

        return processedLines.joined(separator: "\n")
    }
}
