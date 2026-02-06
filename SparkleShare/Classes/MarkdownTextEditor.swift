//
//  MarkdownTextEditor.swift
//  SparkleShare
//
//  UIViewRepresentable wrapper for UITextView with Return/Backspace detection.
//

import SwiftUI
import UIKit

/// A UITextView wrapper that detects special key events for inline editing
struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    let onReturn: (String, String) -> Void    // (textBeforeCursor, textAfterCursor)
    let onBackspaceAtStart: () -> Void
    var onDismiss: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 16)
        textView.backgroundColor = UIColor.secondarySystemBackground
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .default
        textView.text = text
        textView.layer.cornerRadius = 4
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Become first responder to show keyboard
        DispatchQueue.main.async {
            textView.becomeFirstResponder()
        }

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text && !context.coordinator.isEditing {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextEditor
        var isEditing = false

        init(_ parent: MarkdownTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            parent.text = textView.text
            // Notify that editing has ended (user tapped elsewhere or keyboard dismissed)
            parent.onDismiss?()
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        /// Check if the current line is a list item and return the continuation prefix
        private func listContinuation(for textView: UITextView, cursorPosition: Int) -> String? {
            let currentText = textView.text ?? ""
            guard !currentText.isEmpty else { return nil }

            // Find the start of the current line
            let before = currentText.prefix(cursorPosition)
            let lineStart: String.Index
            if let lastNL = before.lastIndex(of: "\n") {
                lineStart = currentText.index(after: lastNL)
            } else {
                lineStart = currentText.startIndex
            }

            // Find the end of the current line
            let cursorIndex = currentText.index(currentText.startIndex, offsetBy: cursorPosition)
            let lineEnd: String.Index
            if let nextNL = currentText[cursorIndex...].firstIndex(of: "\n") {
                lineEnd = nextNL
            } else {
                lineEnd = currentText.endIndex
            }

            let fullLine = String(currentText[lineStart..<lineEnd])
            let indent = String(fullLine.prefix(while: { $0 == " " || $0 == "\t" }))
            let trimmed = fullLine.drop(while: { $0 == " " || $0 == "\t" })

            // Task list: - [ ] or - [x]
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                return "\(indent)- [ ] "
            }
            // Bullet list
            if trimmed.hasPrefix("- ") { return "\(indent)- " }
            if trimmed.hasPrefix("* ") { return "\(indent)* " }
            if trimmed.hasPrefix("+ ") { return "\(indent)+ " }
            // Numbered list: "1. ", "2. ", etc.
            let digits = trimmed.prefix(while: { $0.isNumber })
            if !digits.isEmpty, trimmed.dropFirst(digits.count).hasPrefix(". "),
               let num = Int(digits) {
                return "\(indent)\(num + 1). "
            }

            return nil
        }

        /// Check if a trimmed line is just a list prefix with no content after it
        private func isJustListPrefix(_ trimmed: String) -> Bool {
            if trimmed == "-" || trimmed == "*" || trimmed == "+" { return true }
            if trimmed == "- [ ]" || trimmed == "- [x]" || trimmed == "- [X]" { return true }
            let digits = trimmed.prefix(while: { $0.isNumber })
            if !digits.isEmpty, trimmed.dropFirst(digits.count) == "." { return true }
            return false
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Return key
            if text == "\n" {
                // For list lines, end editing and create a new list item
                if let continuation = listContinuation(for: textView, cursorPosition: range.location) {
                    let currentText = textView.text ?? ""
                    let cursorPos = range.location

                    // Check if the current line is an empty list item (just prefix, no content)
                    let cursorIndex = currentText.index(currentText.startIndex, offsetBy: cursorPos)
                    let lineStart: String.Index
                    if let lastNL = currentText[..<cursorIndex].lastIndex(of: "\n") {
                        lineStart = currentText.index(after: lastNL)
                    } else {
                        lineStart = currentText.startIndex
                    }
                    let lineEnd: String.Index
                    if let nextNL = currentText[cursorIndex...].firstIndex(of: "\n") {
                        lineEnd = nextNL
                    } else {
                        lineEnd = currentText.endIndex
                    }
                    let currentLine = String(currentText[lineStart..<lineEnd])
                    if isJustListPrefix(currentLine.trimmingCharacters(in: .whitespaces)) {
                        // Replace empty list prefix with empty line and exit editing
                        textView.text = ""
                        parent.text = ""
                        parent.onDismiss?()
                        return false
                    }

                    let splitIndex = currentText.index(currentText.startIndex, offsetBy: min(cursorPos, currentText.count))
                    let textBefore = String(currentText[currentText.startIndex..<splitIndex])
                    let textAfter = continuation + String(currentText[splitIndex...])
                    parent.onReturn(textBefore, textAfter)
                    return false
                }
                // For non-list lines, just insert newline and stay in edit mode
                return true
            }

            // Detect Backspace at start of text (no selection)
            if text.isEmpty && range.location == 0 && range.length == 0 {
                parent.onBackspaceAtStart()
                return false
            }

            return true
        }
    }
}
