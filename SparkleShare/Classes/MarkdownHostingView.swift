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
                      endLine: Int)
    func markdownView(_ view: UIView, didInsertTextAtEmptyLine lineNumber: Int,
                      newText: String)
    func markdownView(_ view: UIView, didDeleteEmptyLine lineNumber: Int)
    func markdownView(_ view: UIView, didSplitEmptyLine lineNumber: Int,
                      textBefore: String, textAfter: String)
    func markdownView(_ view: UIView, didMergeEmptyLineWithPrevious lineNumber: Int,
                      text: String)
}

@objc class MarkdownHostingView: UIView {
    @objc weak var delegate: MarkdownViewDelegate?

    private var hostingController: UIHostingController<AnyView>?
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
        updateHostingController()
    }

    @objc func updateWithMarkdown(_ markdown: String) {
        self.originalMarkdown = markdown
        updateHostingController()
    }

    /// Set the line number to focus for editing after the next render
    @objc func setPendingEditingLine(_ lineNumber: Int) {
        self.pendingEditingLineNumber = lineNumber
    }

    /// Clear any pending editing state
    @objc func clearPendingEditing() {
        self.pendingEditingLineNumber = nil
    }

    private func updateHostingController() {
        hostingController?.view.removeFromSuperview()
        hostingController = nil

        // Debug: show the markdown being parsed
        print("DEBUG HOSTING: Parsing markdown with \(originalMarkdown.components(separatedBy: "\n").count) lines")
        let lines = originalMarkdown.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() where i >= 18 && i <= 28 {
            print("DEBUG HOSTING: Line \(i+1): '\(line)' (length: \(line.count))")
        }

        // Parse markdown with location tracking
        let parseResult = MarkdownParser.parseWithLocations(originalMarkdown)

        // Debug output
        print("DEBUG: Parsed markdown, nodeLocations count: \(parseResult.nodeLocations.count)")
        for (key, value) in parseResult.nodeLocations {
            print("DEBUG: nodeLocation[\(key)] = (start: \(value.start), end: \(value.end))")
        }

        // Get and clear pending editing state
        let editingLine = pendingEditingLineNumber
        pendingEditingLineNumber = nil
        if let line = editingLine {
            print("DEBUG HOSTING: Will initialize editing for line \(line)")
        }

        // Create SwiftUI view with editing support
        let view = MarkdownView(
            node: parseResult.ast,
            nodeLocations: parseResult.nodeLocations,
            originalMarkdown: originalMarkdown,
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
                print("DEBUG HOSTING onInsertLineAfter: nodeId=\(nodeId), startLine=\(startLine), endLine=\(endLine)")
                print("DEBUG HOSTING onInsertLineAfter: textBefore='\(textBefore)', textAfter='\(textAfter)'")
                guard let self = self else {
                    print("DEBUG HOSTING: self is nil!")
                    return
                }
                print("DEBUG HOSTING: calling delegate, delegate is \(self.delegate != nil ? "set" : "nil")")
                self.delegate?.markdownView(self, didInsertLineAfterStartLine: startLine,
                                           endLine: endLine, textBefore: textBefore, textAfter: textAfter)
            },
            onMergeWithPrevious: { [weak self] nodeId, startLine, endLine in
                guard let self = self else { return }
                self.delegate?.markdownView(self, didRequestMergeLineAtStart: startLine,
                                           endLine: endLine)
            },
            onInsertAtEmptyLine: { [weak self] lineNumber, newText in
                print("DEBUG HOSTING onInsertAtEmptyLine: lineNumber=\(lineNumber), newText='\(newText)'")
                guard let self = self else { return }
                self.delegate?.markdownView(self, didInsertTextAtEmptyLine: lineNumber,
                                           newText: newText)
            },
            onDeleteEmptyLine: { [weak self] lineNumber in
                print("DEBUG HOSTING onDeleteEmptyLine: lineNumber=\(lineNumber)")
                guard let self = self else { return }
                self.delegate?.markdownView(self, didDeleteEmptyLine: lineNumber)
            },
            onSplitEmptyLine: { [weak self] lineNumber, textBefore, textAfter in
                print("DEBUG HOSTING onSplitEmptyLine: lineNumber=\(lineNumber), before='\(textBefore)', after='\(textAfter)'")
                guard let self = self else { return }
                self.delegate?.markdownView(self, didSplitEmptyLine: lineNumber,
                                           textBefore: textBefore, textAfter: textAfter)
            },
            onMergeEmptyLineWithPrevious: { [weak self] lineNumber, text in
                print("DEBUG HOSTING onMergeEmptyLineWithPrevious: lineNumber=\(lineNumber), text='\(text)'")
                guard let self = self else { return }
                self.delegate?.markdownView(self, didMergeEmptyLineWithPrevious: lineNumber,
                                           text: text)
            },
            initialEditingLineNumber: editingLine
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
}
