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
    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - measuredWidth) > 0.5 { measureHeight() }
    }
    func measureHeight() {
        guard bounds.width > 1 else { return }
        measuredWidth = bounds.width; revision += 1
        let current = revision
        let height = min(140, max(42, ceil(sizeThatFits(CGSize(width: bounds.width, height: .greatestFiniteMagnitude)).height)))
        DispatchQueue.main.async { [weak self] in if self?.revision == current { self?.onHeight?(height) } }
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
