//
//  MarkdownView.swift
//  SparkleShare
//
//  SwiftUI view that renders markdown AST nodes.
//

import SwiftUI

struct MarkdownView: View {
    let node: MarkdownNode
    let onCheckboxToggle: (Int, Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MarkdownNodeView(
                    node: node,
                    onCheckboxToggle: onCheckboxToggle
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(UIColor.systemBackground))
    }
}

struct MarkdownNodeView: View {
    let node: MarkdownNode
    let onCheckboxToggle: (Int, Bool) -> Void

    var body: some View {
        nodeView
    }

    @ViewBuilder
    private var nodeView: some View {
        switch node {
        case .document(let children):
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    MarkdownNodeView(node: child, onCheckboxToggle: onCheckboxToggle)
                }
            }

        case .heading(let level, let children):
            headingView(level: level, children: children)

        case .paragraph(let children):
            paragraphView(children: children)

        case .blockquote(let children):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        MarkdownNodeView(node: child, onCheckboxToggle: onCheckboxToggle)
                    }
                }
            }
            .padding(.vertical, 4)

        case .list(let ordered, let start, _, let children):
            listView(ordered: ordered, start: start, children: children)

        case .listItem(let children):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    MarkdownNodeView(node: child, onCheckboxToggle: onCheckboxToggle)
                }
            }

        case .taskListItem(let index, let checked, let children):
            taskListItemView(index: index, checked: checked, children: children)

        case .codeBlock(_, let literal):
            codeBlockView(literal: literal)

        case .htmlBlock(let literal):
            Text(literal)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)

        case .thematicBreak:
            Divider()
                .padding(.vertical, 8)

        case .table(_, let children):
            tableView(children: children)

        case .tableRow(let children):
            HStack(spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    MarkdownNodeView(node: child, onCheckboxToggle: onCheckboxToggle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        case .tableCell(let children):
            VStack(alignment: .leading) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    MarkdownNodeView(node: child, onCheckboxToggle: onCheckboxToggle)
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
    private func headingView(level: Int, children: [MarkdownNode]) -> some View {
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

        // Use Text composition for inline elements
        let combinedText = children.reduce(Text("")) { result, child in
            result + inlineNodeText(child)
        }

        combinedText
            .font(font)
            .fontWeight(.bold)
            .padding(.top, level <= 2 ? 8 : 4)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func paragraphView(children: [MarkdownNode]) -> some View {
        // Use Text composition for inline elements
        let combinedText = children.reduce(Text("")) { result, child in
            result + inlineNodeText(child)
        }
        combinedText
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func listView(ordered: Bool, start: Int, children: [MarkdownNode]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                // Check if the child is a task list item - if so, don't add bullet/number
                if case .taskListItem = child {
                    MarkdownNodeView(node: child, onCheckboxToggle: onCheckboxToggle)
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
                        MarkdownNodeView(node: child, onCheckboxToggle: onCheckboxToggle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.leading, 8)
    }

    @ViewBuilder
    private func taskListItemView(index: Int, checked: Bool, children: [MarkdownNode]) -> some View {
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
                    MarkdownNodeView(node: child, onCheckboxToggle: onCheckboxToggle)
                        .strikethrough(checked)
                        .foregroundColor(checked ? .secondary : .primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func codeBlockView(literal: String) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(literal.trimmingCharacters(in: .newlines))
                .font(.system(.body, design: .monospaced))
                .padding(12)
        }
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func tableView(children: [MarkdownNode]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                MarkdownNodeView(node: child, onCheckboxToggle: onCheckboxToggle)
                    .background(index == 0 ? Color.gray.opacity(0.1) : Color.clear)
            }
        }
        .overlay(
            Rectangle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .padding(.vertical, 4)
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

        case .paragraph(let children):
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
