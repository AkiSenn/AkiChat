import SwiftUI
import UIKit

/// Observe public UIScrollView properties without replacing SwiftUI's delegate.
final class ScrollFollowController: NSObject, ObservableObject {
    @Published private(set) var following = true
    private weak var scroll: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private var pending: DispatchWorkItem?
    static func nearBottom(offset: CGFloat, content: CGFloat, viewport: CGFloat, bottomInset: CGFloat) -> Bool {
        content + bottomInset - viewport - offset <= 48
    }
    func attach(_ view: UIScrollView) {
        guard scroll !== view else { return }; detach(); scroll = view
        view.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
        observations = [view.observe(\.contentSize, options: [.new]) { [weak self] _, _ in self?.schedule() },
                        view.observe(\.bounds, options: [.new]) { [weak self] _, _ in self?.schedule() },
                        view.observe(\.contentOffset, options: [.new]) { [weak self] view, _ in
                            if view.isDragging || view.isDecelerating { self?.userScrolled(view) }
                        }]
        schedule()
    }
    func detach() {
        pending?.cancel(); pending = nil
        scroll?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
        observations = []; scroll = nil
    }
    func resume() { if !following { following = true }; schedule() }
    func pause() { if following { following = false }; pending?.cancel(); pending = nil }
    private func userScrolled(_ view: UIScrollView) {
        let bottom = Self.nearBottom(offset: view.contentOffset.y, content: view.contentSize.height, viewport: view.bounds.height, bottomInset: view.adjustedContentInset.bottom)
        if following != bottom { following = bottom }
    }
    @objc private func panChanged(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { pause() }
        if gesture.state == .ended || gesture.state == .cancelled, let view = scroll { userScrolled(view); schedule() }
    }
    func schedule() {
        guard following, pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }; self.pending = nil
            guard self.following, let view = self.scroll, !view.isDragging, !view.isDecelerating else { return }
            let target = max(-view.adjustedContentInset.top, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
            if abs(view.contentOffset.y - target) > 1 { view.setContentOffset(CGPoint(x: view.contentOffset.x, y: target), animated: false) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    deinit { pending?.cancel() }
}

struct ScrollMetricsReader: UIViewRepresentable {
    let controller: ScrollFollowController
    final class Marker: UIView {
        weak var controller: ScrollFollowController?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.window != nil else { return }
                var candidate = self.superview
                while let view = candidate {
                    if let scroll = view as? UIScrollView { self.controller?.attach(scroll); return }
                    candidate = view.superview
                }
            }
        }
    }
    func makeUIView(context: Context) -> Marker {
        let view = Marker(); view.controller = controller; view.isUserInteractionEnabled = false; return view
    }
    func updateUIView(_ view: Marker, context: Context) {}
    static func dismantleUIView(_ view: Marker, coordinator: ()) { view.controller?.detach() }
}
