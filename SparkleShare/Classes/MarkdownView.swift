//
//  MarkdownView.swift
//  SparkleShare
//
//  SwiftUI view that renders markdown AST nodes with inline editing support.
//

import SwiftUI

// MARK: - Editing Context (shared via EnvironmentObject)

/// Holds all editing state, callbacks, and cached data for the markdown editing system.
/// Injected as @EnvironmentObject so MarkdownNodeView doesn't need parameter threading.
class MarkdownEditingContext: ObservableObject {
    // AST (published to trigger re-renders)
    @Published var ast: MarkdownNode = .document(id: "empty", children: [])

    // Editing state
    @Published var editingNodeId: String?
    @Published var editingText: String = ""

    // Data (not @Published — updated together with ast)
    var nodeLocations: [String: (start: Int, end: Int)] = [:]
    var originalMarkdown: String = ""

    // Cached line data (recomputed on each markdown update)
    private(set) var lines: [String] = []
    private(set) var emptyLineNumbers: Set<Int> = Set()

    // Callbacks (set once by MarkdownHostingView)
    var onCheckboxToggle: (Int, Bool) -> Void = { _, _ in }
    var onEditComplete: (String, Int, Int, String) -> Void = { _, _, _, _ in }
    var onInsertLineAfter: (String, Int, Int, String, String) -> Void = { _, _, _, _, _ in }
    var onMergeWithPrevious: (String, Int, Int, String) -> Void = { _, _, _, _ in }
    var onInsertAtEmptyLine: (Int, String) -> Void = { _, _ in }
    var onDeleteEmptyLine: (Int) -> Void = { _ in }
    var onSplitEmptyLine: (Int, String, String) -> Void = { _, _, _ in }
    var onMergeEmptyLineWithPrevious: (Int, String) -> Void = { _, _ in }

    /// Update markdown content after a parse. Refreshes cached line data.
    func updateMarkdown(_ markdown: String, locations: [String: (start: Int, end: Int)]) {
        originalMarkdown = markdown
        nodeLocations = locations
        lines = markdown.components(separatedBy: "\n")
        emptyLineNumbers = Set(lines.enumerated()
            .filter { $0.element.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.offset + 1 })
    }

    /// Extract raw markdown lines for a given range (1-based, inclusive)
    func extractLines(start: Int, end: Int) -> String {
        guard start >= 1, end >= start, start <= lines.count else { return "" }
        let endIndex = min(end, lines.count)
        return lines[(start-1)..<endIndex].joined(separator: "\n")
    }

    /// Start editing a node by ID (dismisses any current editing first)
    func startEditing(nodeId: String) {
        dismissEditing()
        if let loc = nodeLocations[nodeId] {
            editingText = extractLines(start: loc.start, end: loc.end)
            editingNodeId = nodeId
        }
    }

    /// Start editing an empty line (dismisses any current editing first)
    func startEditingEmptyLine(_ lineNumber: Int) {
        dismissEditing()
        editingText = ""
        editingNodeId = "emptyline_\(lineNumber)"
    }

    /// Dismiss current editing, saving changes via the appropriate callback
    func dismissEditing() {
        guard let nodeId = editingNodeId else { return }
        let text = editingText
        // Clear state BEFORE calling callbacks to prevent double-save
        // from textViewDidEndEditing firing during view rebuild
        editingNodeId = nil
        editingText = ""

        if nodeId.hasPrefix("emptyline_"),
           let lineNum = Int(nodeId.dropFirst("emptyline_".count)) {
            if !text.isEmpty {
                onInsertAtEmptyLine(lineNum, text)
            }
        } else if let loc = nodeLocations[nodeId] {
            onEditComplete(nodeId, loc.start, loc.end, text)
        }
    }
}

// MARK: - Root View

struct MarkdownView: View {
    @EnvironmentObject var context: MarkdownEditingContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MarkdownNodeView(node: context.ast)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 100)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(UIColor.systemBackground))
    }
}

// MARK: - Node View

struct MarkdownNodeView: View {
    let node: MarkdownNode
    @EnvironmentObject var context: MarkdownEditingContext

    var body: some View {
        nodeView
    }

    // MARK: - Helpers

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

    /// Find actual content end (last non-empty line) within a node's range
    private func actualContentEnd(nodeId: String?) -> Int? {
        guard let id = nodeId, let loc = context.nodeLocations[id] else { return nil }
        for line in stride(from: loc.end, through: loc.start, by: -1) {
            if !context.emptyLineNumbers.contains(line) { return line }
        }
        return loc.start
    }

    /// Find actual content start (first non-empty line) within a node's range
    private func actualContentStart(nodeId: String?) -> Int? {
        guard let id = nodeId, let loc = context.nodeLocations[id] else { return nil }
        for line in loc.start...loc.end {
            if !context.emptyLineNumbers.contains(line) { return line }
        }
        return loc.end
    }

    /// Check if a node or any of its children is being edited
    private func isNodeOrChildBeingEdited(_ node: MarkdownNode) -> Bool {
        switch node {
        case .paragraph(let id, _), .heading(let id, _, _),
             .codeBlock(let id, _, _), .blockquote(let id, _), .table(let id, _, _):
            return context.editingNodeId == id
        case .listItem(_, let children), .taskListItem(_, _, _, let children):
            return children.contains { isNodeOrChildBeingEdited($0) }
        default:
            return false
        }
    }

    /// Get the paragraph node ID from a list item's children
    private func getParagraphIdFromChildren(_ children: [MarkdownNode]) -> String? {
        for child in children {
            if case .paragraph(let id, _) = child { return id }
        }
        return nil
    }

    // MARK: - Shared Editor

    /// Editor for any block-level node (paragraph, heading, codeBlock, blockquote, table)
    @ViewBuilder
    private func nodeEditor(nodeId: String) -> some View {
        if let loc = context.nodeLocations[nodeId] {
            MarkdownTextEditor(
                text: $context.editingText,
                onReturn: { before, after in
                    context.editingNodeId = nil
                    context.editingText = ""
                    context.onInsertLineAfter(nodeId, loc.start, loc.end, before, after)
                },
                onBackspaceAtStart: {
                    let text = context.editingText
                    context.editingNodeId = nil
                    context.editingText = ""
                    context.onMergeWithPrevious(nodeId, loc.start, loc.end, text)
                },
                onDismiss: {
                    guard context.editingNodeId == nodeId else { return }
                    let text = context.editingText
                    context.editingNodeId = nil
                    context.editingText = ""
                    context.onEditComplete(nodeId, loc.start, loc.end, text)
                }
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Node Rendering

    @ViewBuilder
    private var nodeView: some View {
        switch node {
        case .document(_, let children):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                    let childId = getNodeId(child)
                    let prevChild = index > 0 ? children[index - 1] : nil
                    let prevId = prevChild.flatMap { getNodeId($0) }

                    let prevEnd = actualContentEnd(nodeId: prevId)
                    let currStart = actualContentStart(nodeId: childId)

                    // Empty lines between elements
                    if let prevEnd = prevEnd, let currStart = currStart {
                        let emptyLinesInGap = context.emptyLineNumbers.filter { $0 > prevEnd && $0 < currStart }.sorted()
                        ForEach(emptyLinesInGap, id: \.self) { lineNum in
                            emptyLineView(lineNumber: lineNum)
                        }
                    } else if index == 0, let currStart = currStart {
                        let emptyLinesAtStart = context.emptyLineNumbers.filter { $0 < currStart }.sorted()
                        ForEach(emptyLinesAtStart, id: \.self) { lineNum in
                            emptyLineView(lineNumber: lineNum)
                        }
                    }

                    MarkdownNodeView(node: child)
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
                    MarkdownNodeView(node: child)
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
                    MarkdownNodeView(node: child)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        case .tableCell(_, let children):
            VStack(alignment: .leading) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    MarkdownNodeView(node: child)
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
    private func emptyLineView(lineNumber: Int) -> some View {
        let emptyLineId = "emptyline_\(lineNumber)"

        if context.editingNodeId == emptyLineId {
            MarkdownTextEditor(
                text: $context.editingText,
                onReturn: { before, after in
                    context.editingNodeId = nil
                    context.editingText = ""
                    context.onSplitEmptyLine(lineNumber, before, after)
                },
                onBackspaceAtStart: {
                    if context.editingText.isEmpty {
                        context.editingNodeId = nil
                        context.editingText = ""
                        context.onDeleteEmptyLine(lineNumber)
                    } else {
                        let text = context.editingText
                        context.editingNodeId = nil
                        context.editingText = ""
                        context.onMergeEmptyLineWithPrevious(lineNumber, text)
                    }
                },
                onDismiss: {
                    guard context.editingNodeId == emptyLineId else { return }
                    if !context.editingText.isEmpty {
                        let text = context.editingText
                        context.editingNodeId = nil
                        context.editingText = ""
                        context.onInsertAtEmptyLine(lineNumber, text)
                    } else {
                        context.editingNodeId = nil
                        context.editingText = ""
                    }
                }
            )
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack { Spacer() }
                .frame(height: 22)
                .contentShape(Rectangle())
                .onTapGesture {
                    context.startEditingEmptyLine(lineNumber)
                }
        }
    }

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

        if context.editingNodeId == nodeId {
            nodeEditor(nodeId: nodeId)
        } else {
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
            .onTapGesture { context.startEditing(nodeId: nodeId) }
        }
    }

    @ViewBuilder
    private func paragraphView(nodeId: String, children: [MarkdownNode]) -> some View {
        if context.editingNodeId == nodeId {
            nodeEditor(nodeId: nodeId)
        } else {
            let combinedText = children.reduce(Text("")) { result, child in
                result + inlineNodeText(child)
            }
            HStack {
                combinedText
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 22)
            .contentShape(Rectangle())
            .onTapGesture { context.startEditing(nodeId: nodeId) }
        }
    }

    @ViewBuilder
    private func listView(ordered: Bool, start: Int, children: [MarkdownNode]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                if case .taskListItem = child {
                    MarkdownNodeView(node: child)
                } else if case .listItem(_, let itemChildren) = child {
                    let isEditing = isNodeOrChildBeingEdited(child)

                    if isEditing {
                        MarkdownNodeView(node: child)
                    } else {
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
                            MarkdownNodeView(node: child)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let paraId = getParagraphIdFromChildren(itemChildren),
                               let _ = context.nodeLocations[paraId] {
                                context.startEditing(nodeId: paraId)
                            }
                        }
                    }
                } else {
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
                        MarkdownNodeView(node: child)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.leading, 8)
    }

    @ViewBuilder
    private func taskListItemView(index: Int, checked: Bool, children: [MarkdownNode]) -> some View {
        let isEditing = children.contains { isNodeOrChildBeingEdited($0) }

        if isEditing {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    MarkdownNodeView(node: child)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                Button(action: {
                    context.onCheckboxToggle(index, !checked)
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
                        MarkdownNodeView(node: child)
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
        if context.editingNodeId == nodeId {
            nodeEditor(nodeId: nodeId)
        } else {
            Text(literal.trimmingCharacters(in: .newlines))
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { context.startEditing(nodeId: nodeId) }
        }
    }

    @ViewBuilder
    private func blockquoteView(nodeId: String, children: [MarkdownNode]) -> some View {
        if context.editingNodeId == nodeId {
            nodeEditor(nodeId: nodeId)
        } else {
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        MarkdownNodeView(node: child)
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { context.startEditing(nodeId: nodeId) }
        }
    }

    @ViewBuilder
    private func tableView(nodeId: String, children: [MarkdownNode]) -> some View {
        if context.editingNodeId == nodeId {
            nodeEditor(nodeId: nodeId)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                    MarkdownNodeView(node: child)
                        .background(index == 0 ? Color.gray.opacity(0.1) : Color.clear)
                }
            }
            .overlay(
                Rectangle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture { context.startEditing(nodeId: nodeId) }
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
