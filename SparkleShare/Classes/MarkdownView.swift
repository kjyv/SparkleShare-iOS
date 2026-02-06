//
//  MarkdownView.swift
//  SparkleShare
//
//  SwiftUI view that renders markdown AST nodes with inline editing support.
//

import SwiftUI

struct MarkdownView: View {
    let node: MarkdownNode
    let nodeLocations: [String: (start: Int, end: Int)]
    let originalMarkdown: String
    let onCheckboxToggle: (Int, Bool) -> Void

    // Editing callbacks
    let onEditComplete: (String, Int, Int, String) -> Void      // (id, startLine, endLine, newText)
    let onInsertLineAfter: (String, Int, Int, String, String) -> Void // (id, startLine, endLine, textBefore, textAfter)
    let onMergeWithPrevious: (String, Int, Int, String) -> Void  // (id, startLine, endLine, currentText)
    let onInsertAtEmptyLine: (Int, String) -> Void              // (lineNumber, newText) - for editing empty lines
    let onDeleteEmptyLine: (Int) -> Void                        // (lineNumber) - delete empty line
    let onSplitEmptyLine: (Int, String, String) -> Void         // (lineNumber, textBefore, textAfter) - split on Enter
    let onMergeEmptyLineWithPrevious: (Int, String) -> Void     // (lineNumber, text) - merge with previous on Backspace

    // Editing state (shared with MarkdownHostingView via model)
    @Binding var editingNodeId: String?
    @Binding var editingText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MarkdownNodeView(
                    node: node,
                    nodeLocations: nodeLocations,
                    originalMarkdown: originalMarkdown,
                    onCheckboxToggle: onCheckboxToggle,
                    editingNodeId: $editingNodeId,
                    editingText: $editingText,
                    onEditComplete: { nodeId, startLine, endLine, newText in
                        editingNodeId = nil
                        editingText = ""
                        onEditComplete(nodeId, startLine, endLine, newText)
                    },
                    onInsertLineAfter: { nodeId, startLine, endLine, textBefore, textAfter in
                        editingNodeId = nil
                        editingText = ""
                        onInsertLineAfter(nodeId, startLine, endLine, textBefore, textAfter)
                    },
                    onMergeWithPrevious: { nodeId, startLine, endLine, currentText in
                        editingNodeId = nil
                        editingText = ""
                        onMergeWithPrevious(nodeId, startLine, endLine, currentText)
                    },
                    onInsertAtEmptyLine: { lineNumber, newText in
                        editingNodeId = nil
                        editingText = ""
                        onInsertAtEmptyLine(lineNumber, newText)
                    },
                    onDeleteEmptyLine: { lineNumber in
                        editingNodeId = nil
                        editingText = ""
                        onDeleteEmptyLine(lineNumber)
                    },
                    onSplitEmptyLine: { lineNumber, textBefore, textAfter in
                        editingNodeId = nil
                        editingText = ""
                        onSplitEmptyLine(lineNumber, textBefore, textAfter)
                    },
                    onMergeEmptyLineWithPrevious: { lineNumber, text in
                        editingNodeId = nil
                        editingText = ""
                        onMergeEmptyLineWithPrevious(lineNumber, text)
                    },
                    dismissEditing: {
                        guard let nodeId = editingNodeId else { return }
                        let text = editingText
                        // Clear state BEFORE calling callbacks to prevent double-save
                        // from textViewDidEndEditing firing during view rebuild
                        editingNodeId = nil
                        editingText = ""

                        if nodeId.hasPrefix("emptyline_"),
                           let lineNum = Int(nodeId.dropFirst("emptyline_".count)) {
                            // Empty line editing - save if text was entered
                            if !text.isEmpty {
                                onInsertAtEmptyLine(lineNum, text)
                            }
                        } else if let loc = nodeLocations[nodeId] {
                            onEditComplete(nodeId, loc.start, loc.end, text)
                        }
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 100)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(UIColor.systemBackground))
    }
}

struct MarkdownNodeView: View {
    let node: MarkdownNode
    let nodeLocations: [String: (start: Int, end: Int)]
    let originalMarkdown: String
    let onCheckboxToggle: (Int, Bool) -> Void

    // Editing state
    @Binding var editingNodeId: String?
    @Binding var editingText: String

    // Editing callbacks
    let onEditComplete: (String, Int, Int, String) -> Void
    let onInsertLineAfter: (String, Int, Int, String, String) -> Void
    let onMergeWithPrevious: (String, Int, Int, String) -> Void
    let onInsertAtEmptyLine: (Int, String) -> Void
    let onDeleteEmptyLine: (Int) -> Void
    let onSplitEmptyLine: (Int, String, String) -> Void
    let onMergeEmptyLineWithPrevious: (Int, String) -> Void
    let dismissEditing: () -> Void

    /// Get the node ID from a MarkdownNode
    private func getNodeId(_ node: MarkdownNode) -> String? {
        switch node {
        case .document(let id, _), .heading(let id, _, _), .paragraph(let id, _),
             .blockquote(let id, _), .list(let id, _, _, _, _), .listItem(let id, _),
             .taskListItem(let id, _, _, _), .codeBlock(let id, _, _), .htmlBlock(let id, _),
             .thematicBreak(let id), .table(let id, _, _), .tableRow(let id, _), .tableCell(let id, _):
            return id
        default:
            return nil
        }
    }

    var body: some View {
        nodeView
    }

    /// Extract lines from markdown for editing
    private func extractLines(start: Int, end: Int) -> String {
        let lines = originalMarkdown.components(separatedBy: "\n")
        guard start >= 1, end >= start, start <= lines.count else {
            return ""
        }
        let endIndex = min(end, lines.count)
        return lines[(start-1)..<endIndex].joined(separator: "\n")
    }

    /// Get all empty line numbers (1-based) from the original markdown
    private func getEmptyLineNumbers() -> Set<Int> {
        let lines = originalMarkdown.components(separatedBy: "\n")
        return Set(lines.enumerated()
            .filter { $0.element.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.offset + 1 })
    }

    /// Find actual content end (last non-empty line) within a node's range
    private func actualContentEnd(nodeId: String?, emptyLines: Set<Int>) -> Int? {
        guard let id = nodeId, let loc = nodeLocations[id] else { return nil }
        for line in stride(from: loc.end, through: loc.start, by: -1) {
            if !emptyLines.contains(line) {
                return line
            }
        }
        return loc.start
    }

    /// Find actual content start (first non-empty line) within a node's range
    private func actualContentStart(nodeId: String?, emptyLines: Set<Int>) -> Int? {
        guard let id = nodeId, let loc = nodeLocations[id] else { return nil }
        for line in loc.start...loc.end {
            if !emptyLines.contains(line) {
                return line
            }
        }
        return loc.end
    }

    /// View for an empty line that can be tapped to edit
    @ViewBuilder
    private func emptyLineView(lineNumber: Int) -> some View {
        let emptyLineId = "emptyline_\(lineNumber)"

        if editingNodeId == emptyLineId {
            // Edit mode for empty line
            MarkdownTextEditor(
                text: $editingText,
                onReturn: { before, after in
                    // Split: text before cursor stays on this line, text after goes to new line below
                    onSplitEmptyLine(lineNumber, before, after)
                },
                onBackspaceAtStart: {
                    if editingText.isEmpty {
                        // No text - delete the empty line
                        onDeleteEmptyLine(lineNumber)
                    } else {
                        // Has text - merge with previous line
                        onMergeEmptyLineWithPrevious(lineNumber, editingText)
                    }
                },
                onDismiss: {
                    // Only save if we're still the active editor
                    guard editingNodeId == emptyLineId else { return }
                    // If text was entered, save it (replaces the empty line)
                    if !editingText.isEmpty {
                        onInsertAtEmptyLine(lineNumber, editingText)
                    }
                    // If empty, just dismiss (keep the empty line as is)
                    editingNodeId = nil
                    editingText = ""
                }
            )
            .fixedSize(horizontal: false, vertical: true)
        } else {
            // Tappable empty line - height of one line of text
            HStack {
                Spacer()
            }
            .frame(height: 22) // Approximate height of one line of text
            .contentShape(Rectangle())
            .onTapGesture {
                dismissEditing()
                editingText = ""
                editingNodeId = emptyLineId
            }
        }
    }


    /// Check if a node or any of its children is being edited
    private func isNodeOrChildBeingEdited(_ node: MarkdownNode) -> Bool {
        switch node {
        case .paragraph(let id, _), .heading(let id, _, _):
            return editingNodeId == id
        case .listItem(_, let children), .taskListItem(_, _, _, let children):
            return children.contains { isNodeOrChildBeingEdited($0) }
        default:
            return false
        }
    }

    /// Get the paragraph node ID from a list item's children
    private func getParagraphIdFromChildren(_ children: [MarkdownNode]) -> String? {
        for child in children {
            if case .paragraph(let id, _) = child {
                return id
            }
        }
        return nil
    }

    @ViewBuilder
    private var nodeView: some View {
        switch node {
        case .document(_, let children):
            // Find all empty lines in the original markdown
            let emptyLineNumbers = getEmptyLineNumbers()

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                    // Check for empty lines before this child based on actual markdown content
                    let childId = getNodeId(child)
                    let prevChild = index > 0 ? children[index - 1] : nil
                    let prevId = prevChild.flatMap { getNodeId($0) }

                    // Use actual content boundaries, not cmark's extended ranges
                    let prevActualEnd = actualContentEnd(nodeId: prevId, emptyLines: emptyLineNumbers)
                    let currActualStart = actualContentStart(nodeId: childId, emptyLines: emptyLineNumbers)

                    // Find empty lines between previous element's actual content and this one's actual content
                    if let prevEnd = prevActualEnd, let currStart = currActualStart {
                        let emptyLinesInGap = emptyLineNumbers.filter { $0 > prevEnd && $0 < currStart }.sorted()
                        ForEach(emptyLinesInGap, id: \.self) { lineNum in
                            emptyLineView(lineNumber: lineNum)
                        }
                    } else if index == 0, let currStart = currActualStart {
                        // Check for empty lines at the start of document
                        let emptyLinesAtStart = emptyLineNumbers.filter { $0 < currStart }.sorted()
                        ForEach(emptyLinesAtStart, id: \.self) { lineNum in
                            emptyLineView(lineNumber: lineNum)
                        }
                    }

                    // Render the child with standard spacing
                    MarkdownNodeView(
                        node: child,
                        nodeLocations: nodeLocations,
                        originalMarkdown: originalMarkdown,
                        onCheckboxToggle: onCheckboxToggle,
                        editingNodeId: $editingNodeId,
                        editingText: $editingText,
                        onEditComplete: onEditComplete,
                        onInsertLineAfter: onInsertLineAfter,
                        onMergeWithPrevious: onMergeWithPrevious,
                        onInsertAtEmptyLine: onInsertAtEmptyLine,
                        onDeleteEmptyLine: onDeleteEmptyLine,
                        onSplitEmptyLine: onSplitEmptyLine,
                        onMergeEmptyLineWithPrevious: onMergeEmptyLineWithPrevious,
                        dismissEditing: dismissEditing
                    )
                    .padding(.vertical, 8)
                }
            }

        case .heading(let nodeId, let level, let children):
            headingView(nodeId: nodeId, level: level, children: children)

        case .paragraph(let nodeId, let children):
            paragraphView(nodeId: nodeId, children: children)

        case .blockquote(let nodeId, let children):
            blockquoteView(nodeId: nodeId, children: children)

        case .list(_, let ordered, let start, _, let children):
            listView(ordered: ordered, start: start, children: children)

        case .listItem(_, let children):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    MarkdownNodeView(
                        node: child,
                        nodeLocations: nodeLocations,
                        originalMarkdown: originalMarkdown,
                        onCheckboxToggle: onCheckboxToggle,
                        editingNodeId: $editingNodeId,
                        editingText: $editingText,
                        onEditComplete: onEditComplete,
                        onInsertLineAfter: onInsertLineAfter,
                        onMergeWithPrevious: onMergeWithPrevious,
                        onInsertAtEmptyLine: onInsertAtEmptyLine,
                        onDeleteEmptyLine: onDeleteEmptyLine,
                        onSplitEmptyLine: onSplitEmptyLine,
                        onMergeEmptyLineWithPrevious: onMergeEmptyLineWithPrevious,
                        dismissEditing: dismissEditing
                    )
                }
            }

        case .taskListItem(_, let index, let checked, let children):
            taskListItemView(index: index, checked: checked, children: children)

        case .codeBlock(let nodeId, _, let literal):
            codeBlockView(nodeId: nodeId, literal: literal)

        case .htmlBlock(_, let literal):
            Text(literal)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)

        case .thematicBreak:
            Divider()
                .padding(.vertical, 8)

        case .table(let nodeId, _, let children):
            tableView(nodeId: nodeId, children: children)

        case .tableRow(_, let children):
            HStack(spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    MarkdownNodeView(
                        node: child,
                        nodeLocations: nodeLocations,
                        originalMarkdown: originalMarkdown,
                        onCheckboxToggle: onCheckboxToggle,
                        editingNodeId: $editingNodeId,
                        editingText: $editingText,
                        onEditComplete: onEditComplete,
                        onInsertLineAfter: onInsertLineAfter,
                        onMergeWithPrevious: onMergeWithPrevious,
                        onInsertAtEmptyLine: onInsertAtEmptyLine,
                        onDeleteEmptyLine: onDeleteEmptyLine,
                        onSplitEmptyLine: onSplitEmptyLine,
                        onMergeEmptyLineWithPrevious: onMergeEmptyLineWithPrevious,
                        dismissEditing: dismissEditing
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        case .tableCell(_, let children):
            VStack(alignment: .leading) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    MarkdownNodeView(
                        node: child,
                        nodeLocations: nodeLocations,
                        originalMarkdown: originalMarkdown,
                        onCheckboxToggle: onCheckboxToggle,
                        editingNodeId: $editingNodeId,
                        editingText: $editingText,
                        onEditComplete: onEditComplete,
                        onInsertLineAfter: onInsertLineAfter,
                        onMergeWithPrevious: onMergeWithPrevious,
                        onInsertAtEmptyLine: onInsertAtEmptyLine,
                        onDeleteEmptyLine: onDeleteEmptyLine,
                        onSplitEmptyLine: onSplitEmptyLine,
                        onMergeEmptyLineWithPrevious: onMergeEmptyLineWithPrevious,
                        dismissEditing: dismissEditing
                    )
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                Rectangle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )

        case .text(let text):
            Text(text)

        case .softBreak:
            Text(" ")

        case .lineBreak:
            Text("\n")

        case .code(let text):
            Text(text)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(4)

        case .htmlInline(let text):
            Text(text)
                .foregroundColor(.secondary)

        case .emphasis(let children):
            inlineText(children: children, italic: true, bold: false, strikethrough: false)

        case .strong(let children):
            inlineText(children: children, italic: false, bold: true, strikethrough: false)

        case .strikethrough(let children):
            inlineText(children: children, italic: false, bold: false, strikethrough: true)

        case .link(let url, _, let children):
            linkView(url: url, children: children)

        case .image(let url, _, let alt):
            imageView(url: url, alt: alt)
        }
    }

    // MARK: - Component Views

    @ViewBuilder
    private func headingView(nodeId: String, level: Int, children: [MarkdownNode]) -> some View {
        let font: Font = {
            switch level {
            case 1: return .largeTitle
            case 2: return .title
            case 3: return .title2
            case 4: return .title3
            case 5: return .headline
            default: return .subheadline
            }
        }()

        if editingNodeId == nodeId, let loc = nodeLocations[nodeId] {
            // Edit mode
            MarkdownTextEditor(
                text: $editingText,
                onReturn: { before, after in
                    onInsertLineAfter(nodeId, loc.start, loc.end, before, after)
                },
                onBackspaceAtStart: {
                    if editingText.isEmpty {
                        // Empty text - delete the heading
                        onEditComplete(nodeId, loc.start, loc.end, "")
                    } else {
                        // Non-empty text - merge with previous line
                        onMergeWithPrevious(nodeId, loc.start, loc.end, editingText)
                    }
                },
                onDismiss: {
                    // Only save if we're still the active editor (not dismissed by Return/Backspace)
                    guard editingNodeId == nodeId else { return }
                    onEditComplete(nodeId, loc.start, loc.end, editingText)
                }
            )
            .fixedSize(horizontal: false, vertical: true)
        } else {
            // View mode with tap gesture - use HStack to ensure full width hit area
            let combinedText = children.reduce(Text("")) { result, child in
                result + inlineNodeText(child)
            }

            HStack {
                combinedText
                    .font(font)
                    .fontWeight(.bold)
                Spacer(minLength: 0)
            }
            .padding(.top, level <= 2 ? 8 : 4)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                dismissEditing()
                if let loc = nodeLocations[nodeId] {
                    editingText = extractLines(start: loc.start, end: loc.end)
                    editingNodeId = nodeId
                }
            }
        }
    }

    @ViewBuilder
    private func paragraphView(nodeId: String, children: [MarkdownNode]) -> some View {
        if editingNodeId == nodeId, let loc = nodeLocations[nodeId] {
            // Edit mode
            MarkdownTextEditor(
                text: $editingText,
                onReturn: { before, after in
                    onInsertLineAfter(nodeId, loc.start, loc.end, before, after)
                },
                onBackspaceAtStart: {
                    if editingText.isEmpty {
                        // Empty text - delete the paragraph
                        onEditComplete(nodeId, loc.start, loc.end, "")
                    } else {
                        // Non-empty text - merge with previous line (pass current edited text)
                        onMergeWithPrevious(nodeId, loc.start, loc.end, editingText)
                    }
                },
                onDismiss: {
                    // Only save if we're still the active editor (not dismissed by Return/Backspace)
                    guard editingNodeId == nodeId else { return }
                    onEditComplete(nodeId, loc.start, loc.end, editingText)
                }
            )
            .fixedSize(horizontal: false, vertical: true)
        } else {
            // View mode with tap gesture - use HStack to ensure full width hit area
            let combinedText = children.reduce(Text("")) { result, child in
                result + inlineNodeText(child)
            }
            HStack {
                combinedText
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 22) // Ensure tappable area even for empty paragraphs
            .contentShape(Rectangle())
            .onTapGesture {
                dismissEditing()
                if let loc = nodeLocations[nodeId] {
                    editingText = extractLines(start: loc.start, end: loc.end)
                    editingNodeId = nodeId
                }
            }
        }
    }

    @ViewBuilder
    private func listView(ordered: Bool, start: Int, children: [MarkdownNode]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                // Check if the child is a task list item
                if case .taskListItem = child {
                    MarkdownNodeView(
                        node: child,
                        nodeLocations: nodeLocations,
                        originalMarkdown: originalMarkdown,
                        onCheckboxToggle: onCheckboxToggle,
                        editingNodeId: $editingNodeId,
                        editingText: $editingText,
                        onEditComplete: onEditComplete,
                        onInsertLineAfter: onInsertLineAfter,
                        onMergeWithPrevious: onMergeWithPrevious,
                        onInsertAtEmptyLine: onInsertAtEmptyLine,
                        onDeleteEmptyLine: onDeleteEmptyLine,
                        onSplitEmptyLine: onSplitEmptyLine,
                        onMergeEmptyLineWithPrevious: onMergeEmptyLineWithPrevious,
                        dismissEditing: dismissEditing
                    )
                } else if case .listItem(_, let itemChildren) = child {
                    // Check if this list item's paragraph is being edited
                    let isEditing = isNodeOrChildBeingEdited(child)

                    if isEditing {
                        // When editing, show only the editor (no bullet)
                        MarkdownNodeView(
                            node: child,
                            nodeLocations: nodeLocations,
                            originalMarkdown: originalMarkdown,
                            onCheckboxToggle: onCheckboxToggle,
                            editingNodeId: $editingNodeId,
                            editingText: $editingText,
                            onEditComplete: onEditComplete,
                            onInsertLineAfter: onInsertLineAfter,
                            onMergeWithPrevious: onMergeWithPrevious,
                            onInsertAtEmptyLine: onInsertAtEmptyLine,
                            onDeleteEmptyLine: onDeleteEmptyLine,
                            onSplitEmptyLine: onSplitEmptyLine,
                            onMergeEmptyLineWithPrevious: onMergeEmptyLineWithPrevious,
                            dismissEditing: dismissEditing
                        )
                    } else {
                        // Normal view with bullet/number
                        HStack(alignment: .top, spacing: 8) {
                            if ordered {
                                Text("\(start + index).")
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 24, alignment: .trailing)
                            } else {
                                Text("\u{2022}")
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 24, alignment: .center)
                            }
                            MarkdownNodeView(
                                node: child,
                                nodeLocations: nodeLocations,
                                originalMarkdown: originalMarkdown,
                                onCheckboxToggle: onCheckboxToggle,
                                editingNodeId: $editingNodeId,
                                editingText: $editingText,
                                onEditComplete: onEditComplete,
                                onInsertLineAfter: onInsertLineAfter,
                                onMergeWithPrevious: onMergeWithPrevious,
                                onInsertAtEmptyLine: onInsertAtEmptyLine,
                                onDeleteEmptyLine: onDeleteEmptyLine,
                                onSplitEmptyLine: onSplitEmptyLine,
                                onMergeEmptyLineWithPrevious: onMergeEmptyLineWithPrevious,
                                dismissEditing: dismissEditing
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Tap on the row (number/bullet area) — find the paragraph and edit it
                            if let paraId = getParagraphIdFromChildren(itemChildren),
                               let loc = nodeLocations[paraId] {
                                dismissEditing()
                                editingText = extractLines(start: loc.start, end: loc.end)
                                editingNodeId = paraId
                            }
                        }
                    }
                } else {
                    // Fallback for other node types
                    HStack(alignment: .top, spacing: 8) {
                        if ordered {
                            Text("\(start + index).")
                                .foregroundColor(.secondary)
                                .frame(minWidth: 24, alignment: .trailing)
                        } else {
                            Text("\u{2022}")
                                .foregroundColor(.secondary)
                                .frame(minWidth: 24, alignment: .center)
                        }
                        MarkdownNodeView(
                            node: child,
                            nodeLocations: nodeLocations,
                            originalMarkdown: originalMarkdown,
                            onCheckboxToggle: onCheckboxToggle,
                            editingNodeId: $editingNodeId,
                            editingText: $editingText,
                            onEditComplete: onEditComplete,
                            onInsertLineAfter: onInsertLineAfter,
                            onMergeWithPrevious: onMergeWithPrevious,
                            onInsertAtEmptyLine: onInsertAtEmptyLine,
                            onDeleteEmptyLine: onDeleteEmptyLine,
                            onSplitEmptyLine: onSplitEmptyLine,
                            onMergeEmptyLineWithPrevious: onMergeEmptyLineWithPrevious,
                            dismissEditing: dismissEditing
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.leading, 8)
    }

    @ViewBuilder
    private func taskListItemView(index: Int, checked: Bool, children: [MarkdownNode]) -> some View {
        // Check if any child paragraph is being edited
        let isEditing = children.contains { isNodeOrChildBeingEdited($0) }

        if isEditing {
            // When editing, show only the editor (no checkbox)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    MarkdownNodeView(
                        node: child,
                        nodeLocations: nodeLocations,
                        originalMarkdown: originalMarkdown,
                        onCheckboxToggle: onCheckboxToggle,
                        editingNodeId: $editingNodeId,
                        editingText: $editingText,
                        onEditComplete: onEditComplete,
                        onInsertLineAfter: onInsertLineAfter,
                        onMergeWithPrevious: onMergeWithPrevious,
                        onInsertAtEmptyLine: onInsertAtEmptyLine,
                        onDeleteEmptyLine: onDeleteEmptyLine,
                        onSplitEmptyLine: onSplitEmptyLine,
                        onMergeEmptyLineWithPrevious: onMergeEmptyLineWithPrevious,
                        dismissEditing: dismissEditing
                    )
                }
            }
        } else {
            // Normal view with checkbox
            HStack(alignment: .top, spacing: 8) {
                Button(action: {
                    onCheckboxToggle(index, !checked)
                }) {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundColor(checked ? .blue : .gray)
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .frame(minWidth: 24)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        MarkdownNodeView(
                            node: child,
                            nodeLocations: nodeLocations,
                            originalMarkdown: originalMarkdown,
                            onCheckboxToggle: onCheckboxToggle,
                            editingNodeId: $editingNodeId,
                            editingText: $editingText,
                            onEditComplete: onEditComplete,
                            onInsertLineAfter: onInsertLineAfter,
                            onMergeWithPrevious: onMergeWithPrevious,
                            onInsertAtEmptyLine: onInsertAtEmptyLine,
                            onDeleteEmptyLine: onDeleteEmptyLine,
                            onSplitEmptyLine: onSplitEmptyLine,
                            onMergeEmptyLineWithPrevious: onMergeEmptyLineWithPrevious,
                            dismissEditing: dismissEditing
                        )
                        .strikethrough(checked)
                        .foregroundColor(checked ? .secondary : .primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func codeBlockView(nodeId: String, literal: String) -> some View {
        if editingNodeId == nodeId, let loc = nodeLocations[nodeId] {
            MarkdownTextEditor(
                text: $editingText,
                onReturn: { before, after in
                    onInsertLineAfter(nodeId, loc.start, loc.end, before, after)
                },
                onBackspaceAtStart: {
                    if editingText.isEmpty {
                        onEditComplete(nodeId, loc.start, loc.end, "")
                    } else {
                        onMergeWithPrevious(nodeId, loc.start, loc.end, editingText)
                    }
                },
                onDismiss: {
                    guard editingNodeId == nodeId else { return }
                    onEditComplete(nodeId, loc.start, loc.end, editingText)
                }
            )
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(literal.trimmingCharacters(in: .newlines))
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                dismissEditing()
                if let loc = nodeLocations[nodeId] {
                    editingText = extractLines(start: loc.start, end: loc.end)
                    editingNodeId = nodeId
                }
            }
        }
    }

    @ViewBuilder
    private func blockquoteView(nodeId: String, children: [MarkdownNode]) -> some View {
        if editingNodeId == nodeId, let loc = nodeLocations[nodeId] {
            MarkdownTextEditor(
                text: $editingText,
                onReturn: { before, after in
                    onInsertLineAfter(nodeId, loc.start, loc.end, before, after)
                },
                onBackspaceAtStart: {
                    if editingText.isEmpty {
                        onEditComplete(nodeId, loc.start, loc.end, "")
                    } else {
                        onMergeWithPrevious(nodeId, loc.start, loc.end, editingText)
                    }
                },
                onDismiss: {
                    guard editingNodeId == nodeId else { return }
                    onEditComplete(nodeId, loc.start, loc.end, editingText)
                }
            )
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        MarkdownNodeView(
                            node: child,
                            nodeLocations: nodeLocations,
                            originalMarkdown: originalMarkdown,
                            onCheckboxToggle: onCheckboxToggle,
                            editingNodeId: $editingNodeId,
                            editingText: $editingText,
                            onEditComplete: onEditComplete,
                            onInsertLineAfter: onInsertLineAfter,
                            onMergeWithPrevious: onMergeWithPrevious,
                            onInsertAtEmptyLine: onInsertAtEmptyLine,
                            onDeleteEmptyLine: onDeleteEmptyLine,
                            onSplitEmptyLine: onSplitEmptyLine,
                            onMergeEmptyLineWithPrevious: onMergeEmptyLineWithPrevious,
                            dismissEditing: dismissEditing
                        )
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                dismissEditing()
                if let loc = nodeLocations[nodeId] {
                    editingText = extractLines(start: loc.start, end: loc.end)
                    editingNodeId = nodeId
                }
            }
        }
    }

    @ViewBuilder
    private func tableView(nodeId: String, children: [MarkdownNode]) -> some View {
        if editingNodeId == nodeId, let loc = nodeLocations[nodeId] {
            // Edit mode - show raw markdown for the entire table
            MarkdownTextEditor(
                text: $editingText,
                onReturn: { before, after in
                    onInsertLineAfter(nodeId, loc.start, loc.end, before, after)
                },
                onBackspaceAtStart: {
                    if editingText.isEmpty {
                        onEditComplete(nodeId, loc.start, loc.end, "")
                    } else {
                        onMergeWithPrevious(nodeId, loc.start, loc.end, editingText)
                    }
                },
                onDismiss: {
                    guard editingNodeId == nodeId else { return }
                    onEditComplete(nodeId, loc.start, loc.end, editingText)
                }
            )
            .fixedSize(horizontal: false, vertical: true)
        } else {
            // View mode with tap gesture
            VStack(spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                    MarkdownNodeView(
                        node: child,
                        nodeLocations: nodeLocations,
                        originalMarkdown: originalMarkdown,
                        onCheckboxToggle: onCheckboxToggle,
                        editingNodeId: $editingNodeId,
                        editingText: $editingText,
                        onEditComplete: onEditComplete,
                        onInsertLineAfter: onInsertLineAfter,
                        onMergeWithPrevious: onMergeWithPrevious,
                        onInsertAtEmptyLine: onInsertAtEmptyLine,
                        onDeleteEmptyLine: onDeleteEmptyLine,
                        onSplitEmptyLine: onSplitEmptyLine,
                        onMergeEmptyLineWithPrevious: onMergeEmptyLineWithPrevious,
                        dismissEditing: dismissEditing
                    )
                    .background(index == 0 ? Color.gray.opacity(0.1) : Color.clear)
                }
            }
            .overlay(
                Rectangle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                dismissEditing()
                if let loc = nodeLocations[nodeId] {
                    editingText = extractLines(start: loc.start, end: loc.end)
                    editingNodeId = nodeId
                }
            }
        }
    }

    @ViewBuilder
    private func linkView(url: String, children: [MarkdownNode]) -> some View {
        if let linkUrl = URL(string: url) {
            Link(destination: linkUrl) {
                let combinedText = children.reduce(Text("")) { result, child in
                    result + inlineNodeText(child)
                }
                combinedText
                    .foregroundColor(.blue)
                    .underline()
            }
        } else {
            let combinedText = children.reduce(Text("")) { result, child in
                result + inlineNodeText(child)
            }
            combinedText
                .foregroundColor(.blue)
        }
    }

    @ViewBuilder
    private func imageView(url: String, alt: String) -> some View {
        if let imageUrl = URL(string: url) {
            AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(height: 100)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                case .failure:
                    VStack {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                        Text(alt.isEmpty ? "Image" : alt)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                @unknown default:
                    EmptyView()
                }
            }
            .padding(.vertical, 4)
        } else {
            Text("[\(alt)]")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func inlineText(children: [MarkdownNode], italic: Bool, bold: Bool, strikethrough: Bool) -> some View {
        let text = children.reduce(Text("")) { result, child in
            result + inlineNodeText(child)
        }

        text
            .italic(italic)
            .bold(bold)
            .strikethrough(strikethrough)
    }

    // MARK: - Text Building

    private func inlineNodeText(_ node: MarkdownNode) -> Text {
        switch node {
        case .text(let string):
            return Text(string)

        case .code(let string):
            return Text(string)
                .font(.system(.body, design: .monospaced))

        case .emphasis(let children):
            return children.reduce(Text("")) { $0 + inlineNodeText($1) }
                .italic()

        case .strong(let children):
            return children.reduce(Text("")) { $0 + inlineNodeText($1) }
                .bold()

        case .strikethrough(let children):
            return children.reduce(Text("")) { $0 + inlineNodeText($1) }
                .strikethrough()

        case .link(_, _, let children):
            // Links in Text can't be interactive, so just show the text in blue
            return children.reduce(Text("")) { $0 + inlineNodeText($1) }
                .foregroundColor(.blue)

        case .softBreak:
            return Text("\n")

        case .lineBreak:
            return Text("\n")

        case .htmlInline(let string):
            return Text(string)

        case .paragraph(_, let children):
            return children.reduce(Text("")) { $0 + inlineNodeText($1) }

        default:
            return Text("")
        }
    }
}

// MARK: - Text Extensions

extension Text {
    func bold(_ active: Bool) -> Text {
        active ? self.bold() : self
    }

    func italic(_ active: Bool) -> Text {
        active ? self.italic() : self
    }
}
