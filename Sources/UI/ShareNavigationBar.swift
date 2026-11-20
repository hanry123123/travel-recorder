import SwiftUI
import UIKit

/// Persistent native controls outside the editor's scrolling and keyboard area.
/// Next/Done use target/action without navigationBarItems' hosted SwiftUI buttons.
struct ShareNavigationBar: UIViewRepresentable {
    let showingPreview: Bool
    let canShare: Bool
    let onLeft: () -> Void
    let onRight: () -> Void
    func makeUIView(context: Context) -> ShareHeaderView { ShareHeaderView() }
    func updateUIView(_ view: ShareHeaderView, context: Context) {
        view.configure(showingPreview: showingPreview, canShare: canShare, onLeft: onLeft, onRight: onRight)
    }
}

final class ShareHeaderView: UIView {
    let doneButton = UIButton(type: .system)
    let nextButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private var onDone: () -> Void = {}
    private var onNext: () -> Void = {}
    init() {
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        titleLabel.font = .boldSystemFont(ofSize: 17)
        titleLabel.textAlignment = .center
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        doneButton.accessibilityIdentifier = "travel.share.done"
        nextButton.accessibilityIdentifier = "travel.share.next"
        for button in [doneButton, nextButton] {
            button.titleLabel?.font = .systemFont(ofSize: 17)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        }
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        for view in [doneButton, titleLabel, nextButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            doneButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            doneButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            doneButton.heightAnchor.constraint(equalToConstant: 44),
            doneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.heightAnchor.constraint(equalToConstant: 44),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: doneButton.trailingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: nextButton.leadingAnchor, constant: -4)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(showingPreview: Bool, canShare: Bool, onLeft: @escaping () -> Void, onRight: @escaping () -> Void) {
        doneButton.accessibilityIdentifier = showingPreview ? "travel.share.back" : "travel.share.done"
        nextButton.accessibilityIdentifier = showingPreview ? "travel.share.send" : "travel.share.next"
        nextButton.setImage(showingPreview ? UIImage(systemName: "square.and.arrow.up") : nil, for: .normal)
        nextButton.accessibilityLabel = showingPreview ? L("分享旅程") : nil
        configure(title: L(showingPreview ? "分享预览" : "分享旅程"),
                  left: L(showingPreview ? "返回编辑" : "完成"), right: showingPreview ? "" : L("下一步"),
                  enabled: !showingPreview || canShare, onDone: onLeft, onNext: onRight)
    }
    func configure(title: String, left: String, right: String, enabled: Bool, onDone: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.onDone = onDone; self.onNext = onNext
        doneButton.setTitle(left, for: .normal)
        nextButton.setTitle(right, for: .normal)
        nextButton.isEnabled = enabled
        titleLabel.text = title
    }
    @objc private func doneTapped() { onDone() }
    @objc private func nextTapped() { onNext() }
}
