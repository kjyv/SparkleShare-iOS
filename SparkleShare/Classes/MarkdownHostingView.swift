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

// MARK: - UIKit Hosting View

@objc class MarkdownHostingView: UIView {
    @objc weak var delegate: MarkdownViewDelegate?

    private var hostingController: UIHostingController<AnyView>?
    private var context = MarkdownEditingContext()
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
        setupCallbacks()
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

    // MARK: - Setup

    /// Wire up all delegate callbacks on the context (done once)
    private func setupCallbacks() {
        context.onCheckboxToggle = { [weak self] index, checked in
            guard let self = self else { return }
            self.delegate?.markdownView(self, didToggleCheckboxAtIndex: index, checked: checked)
        }
        context.onEditComplete = { [weak self] _, startLine, endLine, newText in
            guard let self = self else { return }
            self.delegate?.markdownView(self, didFinishEditingAtStartLine: startLine,
                                       endLine: endLine, newText: newText)
        }
        context.onInsertLineAfter = { [weak self] _, startLine, endLine, textBefore, textAfter in
            guard let self = self else { return }
            self.delegate?.markdownView(self, didInsertLineAfterStartLine: startLine,
                                       endLine: endLine, textBefore: textBefore, textAfter: textAfter)
        }
        context.onMergeWithPrevious = { [weak self] _, startLine, endLine, currentText in
            guard let self = self else { return }
            self.delegate?.markdownView(self, didRequestMergeLineAtStart: startLine,
                                       endLine: endLine, currentText: currentText)
        }
        context.onInsertAtEmptyLine = { [weak self] lineNumber, newText in
            guard let self = self else { return }
            self.delegate?.markdownView(self, didInsertTextAtEmptyLine: lineNumber,
                                       newText: newText)
        }
        context.onDeleteEmptyLine = { [weak self] lineNumber in
            guard let self = self else { return }
            self.delegate?.markdownView(self, didDeleteEmptyLine: lineNumber)
        }
        context.onSplitEmptyLine = { [weak self] lineNumber, textBefore, textAfter in
            guard let self = self else { return }
            self.delegate?.markdownView(self, didSplitEmptyLine: lineNumber,
                                       textBefore: textBefore, textAfter: textAfter)
        }
        context.onMergeEmptyLineWithPrevious = { [weak self] lineNumber, text in
            guard let self = self else { return }
            self.delegate?.markdownView(self, didMergeEmptyLineWithPrevious: lineNumber,
                                       text: text)
        }
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

    /// Create the hosting controller once with the context as environment object
    private func createHostingController() {
        let view = MarkdownView()
            .environmentObject(context)

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

    /// Update the context with new markdown content (triggers SwiftUI re-render in-place)
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

        // Update context — SwiftUI re-renders in-place, preserving scroll position
        context.updateMarkdown(originalMarkdown, locations: parseResult.nodeLocations)
        context.ast = parseResult.ast

        // Set editing state directly (only when there's a pending edit to activate)
        if resolvedNodeId != nil {
            context.editingNodeId = resolvedNodeId
            context.editingText = resolvedText
        }
    }
}
