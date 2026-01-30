//
//  RecentFilesView.swift
//  SparkleShare
//
//  SwiftUI horizontal scroll view for recently opened files.
//

import SwiftUI
import UIKit

@objc protocol RecentFilesViewDelegate: AnyObject {
    func recentFilesView(_ view: UIView, didSelectRecentFile recentFile: SSRecentFile)
    func recentFilesView(_ view: UIView, didDeleteRecentFile recentFile: SSRecentFile)
    @objc optional func recentFilesView(_ view: UIView, didChangeEditMode isEditMode: Bool)
}

struct RecentFileItem: View {
    let recentFile: SSRecentFile
    let isEditMode: Bool
    let onDelete: () -> Void
    let iconSize: CGFloat = 40

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                if let image = UIImage(forMimeType: recentFile.fileMime, size: UInt32(iconSize * UIScreen.main.scale)) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                } else {
                    Image(systemName: "doc")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                        .foregroundColor(.gray)
                }

                Text(recentFile.fileName)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
            }
            .frame(width: 70, height: 80)

            if isEditMode {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                        .background(Circle().fill(Color.white).frame(width: 16, height: 16))
                }
                .offset(x: 8, y: -4)
            }
        }
    }
}

struct RecentFilesView: View {
    let recentFiles: [SSRecentFile]
    let onSelect: (SSRecentFile) -> Void
    let onDelete: (SSRecentFile) -> Void
    @Binding var isEditMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Files")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 16)

            HStack(spacing: 8) {
                ForEach(Array(recentFiles.prefix(5).enumerated()), id: \.offset) { _, recentFile in
                    Button(action: {
                        if !isEditMode {
                            onSelect(recentFile)
                        }
                    }) {
                        RecentFileItem(
                            recentFile: recentFile,
                            isEditMode: isEditMode,
                            onDelete: { onDelete(recentFile) }
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 1.0)
                            .onEnded { _ in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditMode = true
                                }
                            }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color(UIColor.systemGroupedBackground))
        .onTapGesture {
            if isEditMode {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEditMode = false
                }
            }
        }
    }
}

// UIKit wrapper for hosting the SwiftUI view
@objc class RecentFilesHostingView: UIView {
    @objc weak var delegate: RecentFilesViewDelegate?

    private var hostingController: UIHostingController<AnyView>?
    private var recentFiles: [SSRecentFile] = []
    private var isEditMode: Bool = false

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

    @objc func updateWithRecentFiles(_ files: [SSRecentFile]) {
        self.recentFiles = files
        updateHostingController()
    }

    @objc func exitEditMode() {
        if isEditMode {
            isEditMode = false
            updateHostingController()
            delegate?.recentFilesView?(self, didChangeEditMode: false)
        }
    }

    @objc var isInEditMode: Bool {
        return isEditMode
    }

    private func updateHostingController() {
        hostingController?.view.removeFromSuperview()
        hostingController = nil

        let view = RecentFilesContentView(
            recentFiles: recentFiles,
            initialEditMode: isEditMode,
            onSelect: { [weak self] selectedFile in
                guard let self = self else { return }
                self.delegate?.recentFilesView(self, didSelectRecentFile: selectedFile)
            },
            onDelete: { [weak self] fileToDelete in
                guard let self = self else { return }
                self.delegate?.recentFilesView(self, didDeleteRecentFile: fileToDelete)
            },
            onEditModeChanged: { [weak self] newValue in
                guard let self = self else { return }
                self.isEditMode = newValue
                self.delegate?.recentFilesView?(self, didChangeEditMode: newValue)
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

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 134)
    }
}

// Wrapper view to manage edit mode state
struct RecentFilesContentView: View {
    let recentFiles: [SSRecentFile]
    let initialEditMode: Bool
    let onSelect: (SSRecentFile) -> Void
    let onDelete: (SSRecentFile) -> Void
    let onEditModeChanged: (Bool) -> Void

    @State private var isEditMode: Bool

    init(recentFiles: [SSRecentFile], initialEditMode: Bool, onSelect: @escaping (SSRecentFile) -> Void, onDelete: @escaping (SSRecentFile) -> Void, onEditModeChanged: @escaping (Bool) -> Void) {
        self.recentFiles = recentFiles
        self.initialEditMode = initialEditMode
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onEditModeChanged = onEditModeChanged
        self._isEditMode = State(initialValue: initialEditMode)
    }

    var body: some View {
        RecentFilesView(
            recentFiles: recentFiles,
            onSelect: onSelect,
            onDelete: onDelete,
            isEditMode: Binding(
                get: { isEditMode },
                set: { newValue in
                    isEditMode = newValue
                    onEditModeChanged(newValue)
                }
            )
        )
    }
}
