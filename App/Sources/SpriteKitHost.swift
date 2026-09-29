import CoreGraphics
import SpriteKit

/// What puts painters on a screen (#35): the blit, the frame clock and the finger. `GameController`
/// talks to its painters through one of these and never to a scene, a view or a texture.
///
/// `SpriteKitHost` is the one there is. `ReplayPlayback` is a second in all but name — it drives
/// the same painters with no view, no frame clock and no input — and a watch or a port would be
/// a third (`docs/watch.md` W1, `docs/ports.md` P0).
@MainActor
protocol DerbyHost: AnyObject {
    /// The painter on the glass now; nil before the first `present(_:)`.
    var presented: Painter? { get }

    /// The hard cut (DESIGN.md §3): the painter is on the glass from the next frame on, with no
    /// transition of any kind. A `flashNextFrame` it carries is its first frame.
    func present(_ painter: Painter)

    /// Every painter's canvas, in design pixels.
    func layout(size: CGSize)

    /// A rectangle of a painter's canvas (design pixels, y down) in the view's own points, for an
    /// iPad popover to point at. Nil while that painter is not on the glass.
    func viewRect(of designRect: CGRect, in painter: Painter) -> CGRect?
}

/// The SpriteKit host: one `SKScene` per painter, so a cut is still `presentScene(_:)` with no
/// transition, exactly as it was when the painters were the scenes.
@MainActor
final class SpriteKitHost: DerbyHost {
    private weak var view: SKView?
    private var scenes: [ObjectIdentifier: PainterScene] = [:]

    init(view: SKView, painters: [Painter]) {
        self.view = view
        for painter in painters {
            scenes[ObjectIdentifier(painter)] = PainterScene(painter: painter)
        }
    }

    var presented: Painter? { (view?.scene as? PainterScene)?.painter }

    func present(_ painter: Painter) {
        guard let scene = scenes[ObjectIdentifier(painter)] else {
            assertionFailure("SpriteKitHost has no scene for \(type(of: painter))")
            return
        }
        view?.presentScene(scene)
    }

    func layout(size: CGSize) {
        for scene in scenes.values {
            scene.size = size
            scene.scaleMode = .aspectFit
            scene.painter.size = scene.size
        }
    }

    func viewRect(of designRect: CGRect, in painter: Painter) -> CGRect? {
        guard let scene = scenes[ObjectIdentifier(painter)], let view = scene.view else { return nil }
        // Design space is y down; the scene's own is y up.
        let h = scene.size.height
        let a = view.convert(CGPoint(x: designRect.minX, y: h - designRect.minY), from: scene)
        let b = view.convert(CGPoint(x: designRect.maxX, y: h - designRect.maxY), from: scene)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: max(1, abs(b.x - a.x)), height: max(1, abs(b.y - a.y)))
    }
}

/// One painter's scene: owns the canvas sprite and its texture, turns `update(_:)` into
/// `GameController.tick(_:)`, and hands the painter its touches in design pixels. Only the
/// presented `SKScene` receives `update(_:)` calls from an `SKView`, so this naturally ticks the
/// machine exactly once per real frame regardless of which camera is currently up — there is no
/// need to guard against double-ticking.
@MainActor
private final class PainterScene: SKScene {
    let painter: Painter

    private var canvas: PixelCanvas?
    private var spriteNode: SKSpriteNode?
    private var lastUpdateTime: TimeInterval?

    init(painter: Painter) {
        self.painter = painter
        super.init(size: painter.size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        lastUpdateTime = nil    // time spent off screen is not game time
        rebuildCanvasIfNeeded()
        painter.size = size
        painter.didAppear()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        rebuildCanvasIfNeeded()
        painter.size = size
        painter.sizeDidChange()
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime.map { currentTime - $0 } ?? 0
        lastUpdateTime = currentTime
        painter.advance(dt)
        if painter.ticksMachine { painter.controller?.tick(dt) }

        rebuildCanvasIfNeeded()
        guard let canvas else { return }
        painter.drawFrame(into: canvas)
        blit(canvas)
    }

    // MARK: - Input

    private func designPoint(for touch: UITouch) -> CGPoint {
        let p = touch.location(in: self)
        return CGPoint(x: p.x, y: size.height - p.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        painter.touchBegan(at: designPoint(for: touch))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        painter.touchMoved(to: designPoint(for: touch))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        painter.touchEnded()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        painter.touchCancelled()
    }

    // MARK: - The blit

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
