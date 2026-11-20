import SwiftUI
import UIKit

/// Editor and renderer share the same limits and text attributes. Grapheme counts
/// keep emoji intact; measured line height also bounds newlines and wide glyphs.
enum SharePosterLayout {
    static let titleLimit = 40
    static let bodyLimit = 120
    static let titleRect = CGRect(x: 24, y: 25, width: 672, height: 66)
    static let bodyRect = CGRect(x: 24, y: 1060, width: 672, height: 150)
    static let exportScale: CGFloat = 1.5
    static let posterSize = CGSize(width: 720, height: 1440)

    static func attributes(title: Bool) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = title ? 32 : 30
        paragraph.maximumLineHeight = title ? 32 : 30
        return [.font: title ? UIFont.boldSystemFont(ofSize: 26) : UIFont.systemFont(ofSize: 24),
                .foregroundColor: UIColor.darkText, .paragraphStyle: paragraph]
    }
    static func height(_ text: String, title: Bool) -> CGFloat {
        let rect = title ? titleRect : bodyRect
        return ceil((text as NSString).boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(title: title), context: nil).height)
    }
    static func limited(_ input: String, title: Bool = false) -> String {
        var text = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
        if title { text = text.replacingOccurrences(of: "\n", with: " ") }
        text = String(text.prefix(title ? titleLimit : bodyLimit))
        let maximum = title ? titleRect.height : bodyRect.height
        while !text.isEmpty && height(text, title: title) > maximum { text.removeLast() }
        return text
    }
    static func draw(_ input: String, title: Bool, in context: CGContext) {
        let rect = title ? titleRect : bodyRect
        context.saveGState(); defer { context.restoreGState() }
        context.clip(to: rect)
        (limited(input, title: title) as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(title: title), context: nil)
    }
}

/// Placeholder text never enters UITextView.text or the exported image.
final class ShareInputTextView: UITextView {
    let placeholderLabel = UILabel()
    var placeholder = "" { didSet { refreshPlaceholder() } }
    override var text: String! { didSet { refreshPlaceholder() } }
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.isAccessibilityElement = false
        addSubview(placeholderLabel)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refreshPlaceholder() {
        placeholderLabel.text = placeholder
        placeholderLabel.font = font
        placeholderLabel.isHidden = !(text ?? "").isEmpty
        accessibilityHint = placeholderLabel.isHidden ? nil : placeholder
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let x = textContainerInset.left + textContainer.lineFragmentPadding
        let width = max(0, bounds.width-x-textContainerInset.right-textContainer.lineFragmentPadding)
        let height = placeholderLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        placeholderLabel.frame = CGRect(x: x, y: textContainerInset.top, width: width, height: height)
    }
}

/// Wait for marked text to commit before enforcing a limit, so Chinese input
/// composition is not cut apart. The bounded value is visible in the editor.
struct ShareTextEditor: UIViewRepresentable {
    @Binding var text: String
    var title = false
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> ShareInputTextView {
        let view = ShareInputTextView(frame: .zero, textContainer: nil)
        view.delegate = context.coordinator
        view.backgroundColor = .secondarySystemBackground
        view.font = title ? .boldSystemFont(ofSize: 18) : .systemFont(ofSize: 19)
        view.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        view.layer.cornerRadius = 8
        view.placeholder = AppLanguage.english
            ? (title ? "Give the road you walked a name" : "The roads you walked, the sights you saw, the feelings you want to keep.")
            : (title ? "给走过的路，起个名字" : "走过的路，看过的风景，写下的心情。")
        view.accessibilityLabel = AppLanguage.english ? (title ? "Share title" : "Share text") : (title ? "分享标题" : "分享文字")
        view.accessibilityIdentifier = title ? "travel.share.title" : "travel.share.text"
        return view
    }
    func updateUIView(_ view: ShareInputTextView, context: Context) {
        context.coordinator.parent = self
        guard view.markedTextRange == nil, view.text != text else { return }
        view.text = text
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ShareTextEditor
        init(_ parent: ShareTextEditor) { self.parent = parent }
        func textViewDidChange(_ view: UITextView) {
            (view as? ShareInputTextView)?.refreshPlaceholder()
            guard view.markedTextRange == nil else { return }
            let bounded = SharePosterLayout.limited(view.text, title: parent.title)
            if view.text != bounded {
                let selection = view.selectedRange
                view.text = bounded
                view.selectedRange = NSRange(location: min(selection.location, (bounded as NSString).length), length: 0)
            }
            parent.text = bounded
        }
        func textViewDidEndEditing(_ view: UITextView) { textViewDidChange(view) }
    }
}
