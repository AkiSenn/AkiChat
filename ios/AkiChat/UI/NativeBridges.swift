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
    private lazy var heightProbe = ComposerHeightProbe()
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
        // Keep the native short-input path. For long drafts, establish overflow
        // using a finite container instead of laying out the entire document.
        if ((text ?? "") as NSString).length > 512, let content = attributedText,
           heightProbe.overflows(content, width: bounds.width, insets: textContainerInset,
                                 padding: textContainer.lineFragmentPadding) { return 140 }
        return min(140, max(42, ceil(sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height)))
    }
}

private final class ComposerHeightProbe {
    private let storage = NSTextStorage()
    private let manager = NSLayoutManager()
    private let container = NSTextContainer(size: .zero)
    init() { storage.addLayoutManager(manager); manager.addTextContainer(container) }
    func overflows(_ content: NSAttributedString, width: CGFloat, insets: UIEdgeInsets, padding: CGFloat) -> Bool {
        // Separate measurement storage preserves the editor's native TextKit engine,
        // selection and marked text. Never access UITextView.layoutManager here.
        storage.setAttributedString(content)
        container.lineFragmentPadding = padding
        container.size = CGSize(width: max(1, width - insets.left - insets.right),
                                height: max(1, 140 - insets.top - insets.bottom))
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        return NSMaxRange(characters) < storage.length
    }
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
