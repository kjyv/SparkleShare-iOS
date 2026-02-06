//
//  MarkdownHostingView.swift
//  SparkleShare
//
//  UIKit wrapper for hosting the SwiftUI MarkdownView with inline editing support.
//

import SwiftUI
import UIKit

@objc protocol MarkdownViewDelegate: AnyObject {
    func markdownView(_ view: UIView, didToggleCheckboxAtIndex index: Int, checked: Bool)
    func markdownView(_ view: UIView, didFinishEditingAtStartLine startLine: Int,
                      endLine: Int, newText: String)
    func markdownView(_ view: UIView, didInsertLineAfterStartLine startLine: Int,
                      endLine: Int, textBefore: String, textAfter: String)
    func markdownView(_ view: UIView, didRequestMergeLineAtStart startLine: Int,
                      endLine: Int, currentText: String)
    func markdownView(_ view: UIView, didInsertTextAtEmptyLine lineNumber: Int,
                      newText: String)
    func markdownView(_ view: UIView, didDeleteEmptyLine lineNumber: Int)
    func markdownView(_ view: UIView, didSplitEmptyLine lineNumber: Int,
                      textBefore: String, textAfter: String)
    func markdownView(_ view: UIView, didMergeEmptyLineWithPrevious lineNumber: Int,
                      text: String)
}

// MARK: - Observable model for markdown content

/// Holds the parsed markdown state. Updating properties triggers SwiftUI re-render
/// without recreating the hosting controller, preserving scroll position.
class MarkdownContentModel: ObservableObject {
    @Published var ast: MarkdownNode = .document(id: "empty", children: [])
    @Published var nodeLocations: [String: (start: Int, end: Int)] = [:]
    @Published var originalMarkdown: String = ""
    @Published var editingNodeId: String? = nil
    @Published var editingText: String = ""
}

// MARK: - Container view bridging model to MarkdownView

struct MarkdownContentView: View {
    @ObservedObject var model: MarkdownContentModel
    let onCheckboxToggle: (Int, Bool) -> Void
    let onEditComplete: (String, Int, Int, String) -> Void
    let onInsertLineAfter: (String, Int, Int, String, String) -> Void
    let onMergeWithPrevious: (String, Int, Int, String) -> Void
    let onInsertAtEmptyLine: (Int, String) -> Void
    let onDeleteEmptyLine: (Int) -> Void
    let onSplitEmptyLine: (Int, String, String) -> Void
    let onMergeEmptyLineWithPrevious: (Int, String) -> Void

    var body: some View {
        MarkdownView(
            node: model.ast,
            nodeLocations: model.nodeLocations,
            originalMarkdown: model.originalMarkdown,
            onCheckboxToggle: onCheckboxToggle,
            onEditComplete: onEditComplete,
            onInsertLineAfter: onInsertLineAfter,
            onMergeWithPrevious: onMergeWithPrevious,
            onInsertAtEmptyLine: onInsertAtEmptyLine,
            onDeleteEmptyLine: onDeleteEmptyLine,
            onSplitEmptyLine: onSplitEmptyLine,
            onMergeEmptyLineWithPrevious: onMergeEmptyLineWithPrevious,
            editingNodeId: $model.editingNodeId,
            editingText: $model.editingText
        )
    }
}

// MARK: - UIKit Hosting View

@objc class MarkdownHostingView: UIView {
    @objc weak var delegate: MarkdownViewDelegate?

    private var hostingController: UIHostingController<AnyView>?
    private var contentModel = MarkdownContentModel()
    private var originalMarkdown: String = ""

    // Editing state that persists across re-renders
    private var pendingEditingLineNumber: Int? = nil

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = .systemBackground
        createHostingController()
    }

    @objc func updateWithMarkdown(_ markdown: String) {
        self.originalMarkdown = markdown
        updateContent()
    }

    /// Set the line number to focus for editing after the next render
    @objc func setPendingEditingLine(_ lineNumber: Int) {
        self.pendingEditingLineNumber = lineNumber
    }

    /// Clear any pending editing state
    @objc func clearPendingEditing() {
        self.pendingEditingLineNumber = nil
    }

    /// Walk the AST to find an editable node at the given line number.
    /// This ensures we pick the editable node, not a container like listItem.
    private func findEditableNodeAtLine(_ lineNum: Int, in node: MarkdownNode,
                                        nodeLocations: [String: (start: Int, end: Int)]) -> String? {
        switch node {
        case .paragraph(let id, _), .heading(let id, _, _), .table(let id, _, _),
             .codeBlock(let id, _, _), .blockquote(let id, _):
            if let loc = nodeLocations[id], lineNum >= loc.start && lineNum <= loc.end {
                return id
            }
            return nil
        case .document(_, let children),
             .list(_, _, _, _, let children), .listItem(_, let children),
             .taskListItem(_, _, _, let children):
            for child in children {
                if let found = findEditableNodeAtLine(lineNum, in: child, nodeLocations: nodeLocations) {
                    return found
                }
            }
            return nil
        default:
            return nil
        }
    }

    /// Create the hosting controller once with a container view that observes the model
    private func createHostingController() {
        let view = MarkdownContentView(
            model: contentModel,
            onCheckboxToggle: { [weak self] index, checked in
                guard let self = self else { return }
                self.delegate?.markdownView(self, didToggleCheckboxAtIndex: index, checked: checked)
            },
            onEditComplete: { [weak self] nodeId, startLine, endLine, newText in
                guard let self = self else { return }
                self.delegate?.markdownView(self, didFinishEditingAtStartLine: startLine,
                                           endLine: endLine, newText: newText)
            },
            onInsertLineAfter: { [weak self] nodeId, startLine, endLine, textBefore, textAfter in
                guard let self = self else { return }
                self.delegate?.markdownView(self, didInsertLineAfterStartLine: startLine,
                                           endLine: endLine, textBefore: textBefore, textAfter: textAfter)
            },
            onMergeWithPrevious: { [weak self] nodeId, startLine, endLine, currentText in
                guard let self = self else { return }
                self.delegate?.markdownView(self, didRequestMergeLineAtStart: startLine,
                                           endLine: endLine, currentText: currentText)
            },
            onInsertAtEmptyLine: { [weak self] lineNumber, newText in
                guard let self = self else { return }
                self.delegate?.markdownView(self, didInsertTextAtEmptyLine: lineNumber,
                                           newText: newText)
            },
            onDeleteEmptyLine: { [weak self] lineNumber in
                guard let self = self else { return }
                self.delegate?.markdownView(self, didDeleteEmptyLine: lineNumber)
            },
            onSplitEmptyLine: { [weak self] lineNumber, textBefore, textAfter in
                guard let self = self else { return }
                self.delegate?.markdownView(self, didSplitEmptyLine: lineNumber,
                                           textBefore: textBefore, textAfter: textAfter)
            },
            onMergeEmptyLineWithPrevious: { [weak self] lineNumber, text in
                guard let self = self else { return }
                self.delegate?.markdownView(self, didMergeEmptyLineWithPrevious: lineNumber,
                                           text: text)
            }
        )

        let hosting = UIHostingController(rootView: AnyView(view))
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear

        addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        hostingController = hosting
    }

    /// Update the model with new markdown content (triggers SwiftUI re-render in-place)
    private func updateContent() {
        let parseResult = MarkdownParser.parseWithLocations(originalMarkdown)

        // Get and clear pending editing state, resolve to node ID
        let editingLine = pendingEditingLineNumber
        pendingEditingLineNumber = nil

        var resolvedNodeId: String? = nil
        var resolvedText: String = ""

        if let lineNum = editingLine {
            let lines = originalMarkdown.components(separatedBy: "\n")
            let lineIndex = lineNum - 1

            if lineIndex >= 0 && lineIndex < lines.count &&
               lines[lineIndex].trimmingCharacters(in: .whitespaces).isEmpty {
                resolvedNodeId = "emptyline_\(lineNum)"
                resolvedText = ""
            } else {
                // Walk the AST to find an editable node at this line
                if let nodeId = findEditableNodeAtLine(lineNum, in: parseResult.ast,
                                                       nodeLocations: parseResult.nodeLocations) {
                    if let loc = parseResult.nodeLocations[nodeId] {
                        let endIdx = min(loc.end, lines.count)
                        resolvedText = lines[(loc.start - 1)..<endIdx].joined(separator: "\n")
                        resolvedNodeId = nodeId
                    }
                }
            }
        }

        // Update model — SwiftUI re-renders in-place, preserving scroll position
        contentModel.ast = parseResult.ast
        contentModel.nodeLocations = parseResult.nodeLocations
        contentModel.originalMarkdown = originalMarkdown
        // Set editing state directly (only when there's a pending edit to activate)
        if resolvedNodeId != nil {
            contentModel.editingNodeId = resolvedNodeId
            contentModel.editingText = resolvedText
        }
    }
}
