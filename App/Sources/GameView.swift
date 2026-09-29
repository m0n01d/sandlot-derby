import SwiftUI
import SpriteKit
import UIKit

/// Wraps a plain `SKView`, not SwiftUI's `SpriteView` — `SpriteKitHost` needs to call
/// `presentScene(_:)` directly so the camera cut is a genuine hard cut with no transition,
/// which `SpriteView` does not expose.
struct GameView: UIViewRepresentable {
    let controller: GameController

    func makeUIView(context: Context) -> SandlotSKView {
        let view = SandlotSKView()
        view.controller = controller
        view.ignoresSiblingOrder = true
        #if DEBUG
        view.showsFPS = true
        view.showsNodeCount = true
        #endif
        view.backgroundColor = .black
        controller.attach(to: SpriteKitHost(view: view, painters: controller.painters), in: view)
        return view
    }

    func updateUIView(_ uiView: SandlotSKView, context: Context) {}
}

/// An `SKView` that reports its own size to `GameController` on every layout pass, since the
/// controller needs the live view size to compute the (width, 224) scene size.
final class SandlotSKView: SKView {
    weak var controller: GameController?

    override func layoutSubviews() {
        super.layoutSubviews()
        controller?.updateLayout(viewSize: bounds.size, safeArea: safeAreaInsets)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    #if DEBUG
    // Space bar is the dev slice (DESIGN.md §5). Needs first responder to see key presses.
    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.key?.keyCode == .keyboardSpacebar }) {
            controller?.atBatScene.devSlice()
        } else {
            super.pressesBegan(presses, with: event)
        }
    }
    #endif
}
