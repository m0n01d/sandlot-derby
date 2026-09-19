import SpriteKit

/// Shared machinery for a scene that owns one canvas sprite and ticks `GameController` from
/// `update(_:)`. Only the presented `SKScene` receives `update(_:)` calls from an `SKView`, so
/// this naturally ticks the machine exactly once per real frame regardless of which camera is
/// currently up — there is no need to guard against double-ticking.
class CanvasScene: SKScene {
    weak var controller: GameController?

    /// Set by `GameController` right before `presentScene(_:)` on a `.flash` transition;
    /// consumed by this scene's very next frame instead of its normal draw — the one white
    /// frame of the hard cut (DESIGN.md §3).
    var flashNextFrame = false

    /// The view's horizontal safe-area insets in design pixels, set by `GameController` on
    /// layout. Backgrounds ignore them; anything that must be seen stays inside.
    var safeLeft = 0.0
    var safeRight = 0.0

    private(set) var canvas: PixelCanvas?
    private var spriteNode: SKSpriteNode?
    private var lastUpdateTime: TimeInterval?

    override func didMove(to view: SKView) {
        backgroundColor = .black
        rebuildCanvasIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        rebuildCanvasIfNeeded()
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime.map { currentTime - $0 } ?? 0
        lastUpdateTime = currentTime
        controller?.tick(dt)

        rebuildCanvasIfNeeded()
        guard let canvas else { return }
        if flashNextFrame {
            canvas.fill(Palette.chalk)
            flashNextFrame = false
        } else {
            render(into: canvas)
        }
        blit(canvas)
    }

    /// Subclasses draw one whole frame here, reading only from `controller?.machine`.
    func render(into canvas: PixelCanvas) {}

    private func rebuildCanvasIfNeeded() {
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))
        if let canvas, canvas.width == w, canvas.height == h { return }
        let newCanvas = PixelCanvas(width: w, height: h)
        canvas = newCanvas

        let texture = SKMutableTexture(size: CGSize(width: w, height: h))
        texture.filteringMode = .nearest
        if let spriteNode {
            spriteNode.texture = texture
            spriteNode.size = CGSize(width: w, height: h)
            spriteNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        } else {
            let node = SKSpriteNode(texture: texture, size: CGSize(width: w, height: h))
            node.position = CGPoint(x: size.width / 2, y: size.height / 2)
            addChild(node)
            spriteNode = node
        }
    }

    private func blit(_ canvas: PixelCanvas) {
        guard let texture = spriteNode?.texture as? SKMutableTexture else { return }
        let width = canvas.width
        let height = canvas.height
        let rowBytes = width * 4
        texture.modifyPixelData { rawPointer, _ in
            guard let rawPointer else { return }
            // Design space is y-down (row 0 = top); SpriteKit is y-up and
            // SKMutableTexture's row 0 is the BOTTOM row, so flip rows on copy.
            let src = UnsafeRawPointer(canvas.buffer)
            for row in 0..<height {
                (rawPointer + (height - 1 - row) * rowBytes)
                    .copyMemory(from: src + row * rowBytes, byteCount: rowBytes)
            }
        }
    }
}
