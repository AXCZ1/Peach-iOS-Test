import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

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
    var allowsDownwardDismiss = false
    var onDismissChanged: (CGFloat) -> Void = { _ in }
    var onDismissEnded: (Bool) -> Void = { _ in }
    var onTimedTap: ((CGFloat, TimeInterval) -> Void)? = nil

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
    private var dismissPan = false
    func install() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.minimumPressDuration = 0.45
        hold.allowableMovement = 12
        hold.delegate = self
        addGestureRecognizer(hold)
        addGestureRecognizer(pan)
        if coordinator?.parent.onTimedTap != nil {
            let tap = TimestampedTap(target: self, action: #selector(handleTimedTap(_:)))
            tap.require(toFail: hold)
            addGestureRecognizer(tap)
        } else {
            let double = UITapGestureRecognizer(target: self, action: #selector(handleDouble(_:)))
            double.numberOfTapsRequired = 2
            let single = UITapGestureRecognizer(target: self, action: #selector(handleSingle(_:)))
            single.require(toFail: double)
            single.require(toFail: hold)
            double.require(toFail: hold)
            addGestureRecognizer(single)
            addGestureRecognizer(double)
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        guard let parent = coordinator?.parent else { return false }
        let velocity = pan.velocity(in: self)
        dismissPan = parent.allowsDownwardDismiss && velocity.y > abs(velocity.x) * 1.4
        return dismissPan || (parent.allowsHorizontalSeek && abs(velocity.x) > abs(velocity.y) * 1.4)
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

    @objc private func handleTimedTap(_ recognizer: TimestampedTap) {
        coordinator?.parent.onTimedTap?(recognizer.location(in: self).x / max(bounds.width, 1), recognizer.timestamp)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        // Use the parent as the coordinate space while the player follows the finger.
        let translation = recognizer.translation(in: superview)
        if dismissPan {
            switch recognizer.state {
            case .began, .changed: coordinator?.parent.onDismissChanged(max(0, translation.y))
            case .ended: coordinator?.parent.onDismissEnded(translation.y >= 80)
            case .cancelled, .failed: coordinator?.parent.onDismissEnded(false)
            default: break
            }
            return
        }
        let distance = translation.x
        switch recognizer.state {
        case .began:
            coordinator?.parent.onSeekBegan()
        case .changed:
            coordinator?.parent.onSeekChanged(distance)
        case .ended:
            coordinator?.parent.onSeekEnded(distance)
        case .cancelled, .failed:
            coordinator?.parent.onSeekCancelled()
        default:
            break
        }
    }
}

private final class TimestampedTap: UITapGestureRecognizer {
    private(set) var timestamp: TimeInterval = 0

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        timestamp = touches.first?.timestamp ?? event.timestamp
        super.touchesEnded(touches, with: event)
    }
}
