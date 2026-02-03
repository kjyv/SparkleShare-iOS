//
//  MarkdownHostingView.swift
//  SparkleShare
//
//  UIKit wrapper for hosting the SwiftUI MarkdownView.
//

import SwiftUI
import UIKit

@objc protocol MarkdownViewDelegate: AnyObject {
    func markdownView(_ view: UIView, didToggleCheckboxAtIndex index: Int, checked: Bool)
}

@objc class MarkdownHostingView: UIView {
    @objc weak var delegate: MarkdownViewDelegate?

    private var hostingController: UIHostingController<AnyView>?
    private var markdown: String = ""

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
        self.markdown = markdown
        updateHostingController()
    }

    private func updateHostingController() {
        hostingController?.view.removeFromSuperview()
        hostingController = nil

        // Parse markdown
        let ast = MarkdownParser.parse(markdown)

        // Create SwiftUI view
        let view = MarkdownView(
            node: ast,
            onCheckboxToggle: { [weak self] index, checked in
                guard let self = self else { return }
                self.delegate?.markdownView(self, didToggleCheckboxAtIndex: index, checked: checked)
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
}
