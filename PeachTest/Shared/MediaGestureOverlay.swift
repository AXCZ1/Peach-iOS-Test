import SwiftUI
import UIKit

/// Transparent gesture layer for immersive playback. A horizontal pan seeks and
/// must not steal vertical paging; a vertical pan is declined so the enclosing
/// ScrollView receives it. Double-tap locations are normalized to this view,
/// not UIScreen, so the 25/50/25 regions survive rotation and letterboxing.
struct MediaGestureOverlay: UIViewRepresentable {
    var onTap: () -> Void
    var onDoubleTap: (CGFloat) -> Void
    var onSeekChanged: (CGFloat) -> Void
    var onSeekEnded: (CGFloat) -> Void
    var allowsHorizontalSeek = true
    var onSeekBegan: () -> Void = {}
    var onSeekCancelled: () -> Void = {}
    var onHoldBegan: () -> Void = {}
    var onHoldEnded: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GestureView {
        let view = GestureView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.coordinator = context.coordinator
        view.install()
        return view
    }

    func updateUIView(_ view: GestureView, context: Context) {
        context.coordinator.parent = self
        view.coordinator = context.coordinator
    }

    final class Coordinator {
        var parent: MediaGestureOverlay

        init(_ parent: MediaGestureOverlay) {
            self.parent = parent
        }
    }
}

final class GestureView: UIView, UIGestureRecognizerDelegate {
    weak var coordinator: MediaGestureOverlay.Coordinator?
    private var pan: UIPanGestureRecognizer?
    private var single: UITapGestureRecognizer?
    private var double: UITapGestureRecognizer?

    func install() {
        let double = UITapGestureRecognizer(target: self, action: #selector(handleDouble(_:)))
        double.numberOfTapsRequired = 2
        let single = UITapGestureRecognizer(target: self, action: #selector(handleSingle(_:)))
        single.numberOfTapsRequired = 1
        single.require(toFail: double)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.minimumPressDuration = 0.45
        hold.allowableMovement = 12
        hold.delegate = self
        single.require(toFail: hold)
        double.require(toFail: hold)
        addGestureRecognizer(hold)
        addGestureRecognizer(pan)
        addGestureRecognizer(single)
        addGestureRecognizer(double)
        self.pan = pan
        self.single = single
        self.double = double
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        guard coordinator?.parent.allowsHorizontalSeek == true else { return false }
        let velocity = pan.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y) * 1.4
    }

    @objc private func handleHold(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began: coordinator?.parent.onHoldBegan()
        case .ended, .cancelled, .failed: coordinator?.parent.onHoldEnded()
        default: break
        }
    }

    @objc private func handleSingle(_ recognizer: UITapGestureRecognizer) {
        coordinator?.parent.onTap()
    }

    @objc private func handleDouble(_ recognizer: UITapGestureRecognizer) {
        coordinator?.parent.onDoubleTap(recognizer.location(in: self).x / max(bounds.width, 1))
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self).x
        switch recognizer.state {
        case .began:
            coordinator?.parent.onSeekBegan()
        case .changed:
            coordinator?.parent.onSeekChanged(translation)
        case .ended:
            coordinator?.parent.onSeekEnded(translation)
        case .cancelled, .failed:
            coordinator?.parent.onSeekCancelled()
        default:
            break
        }
    }
}
