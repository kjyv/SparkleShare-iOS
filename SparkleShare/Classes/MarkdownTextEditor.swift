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
        textView.inputAccessoryView = Self.makeKeyboardToolbar(target: context.coordinator,
                                                                action: #selector(Coordinator.dismissKeyboard))
        context.coordinator.setTextView(textView)

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

    static func makeKeyboardToolbar(target: Any, action: Selector) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 36))
        container.backgroundColor = .clear

        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        let image = UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: config)

        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.addTarget(target, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 36)
        ])

        container.layer.zPosition = 9999
        container.isHidden = true
        return container
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextEditor
        var isEditing = false
        private var keyboardObservers: [Any] = []

        init(_ parent: MarkdownTextEditor) {
            self.parent = parent
            super.init()
            let showObs = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
            ) { [weak self] notification in
                // Only show toolbar when software keyboard is present (not just prediction bar)
                if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                   frame.height > 120 {
                    self?.setToolbarHidden(false)
                }
            }
            let hideObs = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.setToolbarHidden(true)
            }
            keyboardObservers = [showObs, hideObs]
        }

        deinit {
            keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        private weak var textView: UITextView?

        func setTextView(_ tv: UITextView) {
            textView = tv
        }

        private func setToolbarHidden(_ hidden: Bool) {
            textView?.inputAccessoryView?.isHidden = hidden
        }

        @objc func dismissKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
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
