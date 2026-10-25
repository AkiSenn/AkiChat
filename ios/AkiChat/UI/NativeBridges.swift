import SwiftUI
import UIKit

struct GrowingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    func makeUIView(context: Context) -> ComposerTextView {
        let view = ComposerTextView()
        view.font = .systemFont(ofSize: 16)
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityLabel = "消息输入框"
        view.accessibilityIdentifier = "message-input"
        view.onHeight = { [weak coordinator = context.coordinator] value in
            guard let coordinator = coordinator, abs(coordinator.parent.height - value) > 0.5 else { return }
            coordinator.parent.height = value
        }
        return view
    }
    func updateUIView(_ view: ComposerTextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text; view.measureHeight() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingTextView
        init(_ parent: GrowingTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text; (textView as? ComposerTextView)?.measureHeight() }
    }
}
final class ComposerTextView: UITextView {
    var onHeight: ((CGFloat) -> Void)?
    private var measuredWidth: CGFloat = 0
    private var revision = 0
    private var saturatedPrefixEnd = 0
    private var sizingWidth: CGFloat = 0
    private var sizingInsets = UIEdgeInsets.zero
    private var sizingPadding: CGFloat = 0
    private var sizingFont: UIFont?
    private weak var observedStorage: NSTextStorage?
    private var storageObserver: NSObjectProtocol?
    private lazy var prefixSizer = UITextView()
    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - measuredWidth) > 0.5 { measureHeight() }
    }
    func measureHeight() {
        guard bounds.width > 1 else { return }
        measuredWidth = bounds.width; revision += 1
        let current = revision
        let height = fittingComposerHeight()
        DispatchQueue.main.async { [weak self] in if self?.revision == current { self?.onHeight?(height) } }
    }
    func fittingComposerHeight() -> CGFloat {
        if saturatedPrefixEnd > 0 {
            if sizingWidth == bounds.width, sizingInsets == textContainerInset,
               sizingPadding == textContainer.lineFragmentPadding, sizingFont == font,
               observedStorage === textStorage { return 140 }
            saturatedPrefixEnd = 0
        }
        let height = min(140, max(42, ceil(sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height)))
        if height == 140 { cacheSaturatedPrefixIfPossible() }
        return height
    }
    private func cacheSaturatedPrefixIfPossible() {
        let storage = textStorage
        guard storage.length > 512 else { return }
        let prefix = (storage.string as NSString).substring(to: 512) as NSString
        let newline = prefix.range(of: "\n", options: .backwards)
        guard newline.location != NSNotFound, newline.location > 0 else { return }
        var end = newline.location
        if prefix.character(at: end - 1) == 13 { end -= 1 } // exclude CRLF, including its extra empty line
        guard end > 0 else { return }
        // A completed paragraph prefix is independent of later edits. Measure
        // without its final newline so the proof excludes the trailing empty line.
        prefixSizer.font = font
        prefixSizer.textContainerInset = textContainerInset
        prefixSizer.textContainer.lineFragmentPadding = textContainer.lineFragmentPadding
        prefixSizer.attributedText = storage.attributedSubstring(from: NSRange(location: 0, length: end))
        guard ceil(prefixSizer.sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height) >= 140 else { return }
        if observedStorage !== storage {
            if let token = storageObserver { NotificationCenter.default.removeObserver(token) }
            observedStorage = storage
            storageObserver = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { [weak self] note in
                guard let self = self, let changed = note.object as? NSTextStorage else { return }
                if changed.editedRange.location < self.saturatedPrefixEnd { self.saturatedPrefixEnd = 0 }
            }
        }
        saturatedPrefixEnd = NSMaxRange(newline)
        sizingWidth = bounds.width; sizingInsets = textContainerInset
        sizingPadding = textContainer.lineFragmentPadding; sizingFont = font
    }
    deinit { if let token = storageObserver { NotificationCenter.default.removeObserver(token) } }
}
struct ShareFile: Identifiable {
    var id = UUID()
    var url: URL
    static func make(data: Data, ext: String) throws -> ShareFile {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AkiChat-\(UUID().uuidString).\(ext)")
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return ShareFile(url: url)
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url) }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
