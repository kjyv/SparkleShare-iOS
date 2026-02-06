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

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Detect Return key
            if text == "\n" {
                let currentText = textView.text ?? ""
                let cursorPosition = range.location

                // Split text at cursor position
                let startIndex = currentText.startIndex
                let splitIndex = currentText.index(startIndex, offsetBy: min(cursorPosition, currentText.count))
                let textBefore = String(currentText[startIndex..<splitIndex])
                let textAfter = String(currentText[splitIndex...])

                print("DEBUG RETURN: Detected Return key press")
                print("DEBUG RETURN: cursorPosition=\(cursorPosition), textBefore='\(textBefore)', textAfter='\(textAfter)'")
                parent.onReturn(textBefore, textAfter)
                return false
            }

            // Detect Backspace at start of text
            if text.isEmpty && range.location == 0 && range.length == 0 {
                print("DEBUG BACKSPACE: Detected backspace at start")
                parent.onBackspaceAtStart()
                return false
            }

            return true
        }
    }
}
