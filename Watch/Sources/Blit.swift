import CoreGraphics
import SpriteKit
import SwiftUI
import WatchKit

/// The glass, measured once: its size in physical pixels and the canvas that fits it.
@MainActor
struct Glass {
    let pointSize: CGSize
    let screenScale: CGFloat
    let pixelWidth: Int
    let pixelHeight: Int
    let canvas: WatchCanvas

    static let current: Glass = {
        let device = WKInterfaceDevice.current()
        let bounds = device.screenBounds.size
        let scale = device.screenScale
        let pw = Int((bounds.width * scale).rounded())
        let ph = Int((bounds.height * scale).rounded())
        let canvas = WatchCanvas.fit(pixelWidth: pw, pixelHeight: ph)
            ?? WatchCanvas(scale: 1, width: pw, height: ph, originX: 0, originY: 0)
        return Glass(pointSize: bounds, screenScale: scale, pixelWidth: pw, pixelHeight: ph, canvas: canvas)
    }()

    /// The canvas's size on the glass in points: exactly `scale` physical pixels a unit.
    var canvasPoints: CGSize {
        CGSize(width: CGFloat(canvas.width * canvas.scale) / screenScale,
               height: CGFloat(canvas.height * canvas.scale) / screenScale)
    }

    /// Where its top-left corner goes, in points, snapped to the pixel grid.
    var canvasOrigin: CGPoint {
        CGPoint(x: CGFloat(canvas.originX) / screenScale, y: CGFloat(canvas.originY) / screenScale)
    }
}

/// A `PixelCanvas` as a `CGImage`. The canvas stores R, G, B, A in memory order and every pixel
/// is opaque, so the bytes go across as they are.
enum CanvasImage {
    static func make(_ c: PixelCanvas) -> CGImage? {
        let bytes = c.width * c.height * 4
        let data = Data(bytes: UnsafeRawPointer(c.buffer), count: bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: c.width, height: c.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: c.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}

/// Counts frames and reports the rate over the last second.
final class FrameCounter {
    private var stamps: [TimeInterval] = []
    private(set) var frames = 0

    func tick(_ now: TimeInterval) -> Int {
        frames += 1
        stamps.append(now)
        stamps.removeAll { now - $0 > 1 }
        return stamps.count
    }
}

/// Path 1: the canvas as a SwiftUI image, redrawn every display frame by a `TimelineView`. This
/// is the spec's fallback (docs/watch.md §2).
@MainActor
struct ImageBlitView: View {
    let draw: (PixelCanvas, Int, Int) -> Void     // canvas, frame number, measured fps
    private let glass = Glass.current
    @State private var canvas = PixelCanvas(width: Glass.current.canvas.width,
                                            height: Glass.current.canvas.height)
    @State private var counter = FrameCounter()

    init(draw: @escaping (PixelCanvas, Int, Int) -> Void) {
        self.draw = draw
    }

    var body: some View {
        TimelineView(.animation) { context in
            let fps = counter.tick(context.date.timeIntervalSinceReferenceDate)
            let _ = draw(canvas, counter.frames, fps)
            if let image = CanvasImage.make(canvas) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: glass.canvasPoints.width, height: glass.canvasPoints.height)
            }
        }
    }
}

/// Path 2: the spec's first choice (docs/watch.md §2) — one `SKScene`, one sprite, one
/// nearest-filtered `SKMutableTexture`, rewritten every frame.
@MainActor
struct SpriteBlitView: View {
    let draw: (PixelCanvas, Int, Int) -> Void
    private let glass = Glass.current
    @State private var scene: BlitScene

    init(draw: @escaping (PixelCanvas, Int, Int) -> Void) {
        self.draw = draw
        _scene = State(initialValue: BlitScene(canvas: Glass.current.canvas, draw: draw))
    }

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60)
            .frame(width: glass.canvasPoints.width, height: glass.canvasPoints.height)
    }
}

final class BlitScene: SKScene {
    private let canvas: PixelCanvas
    private let draw: (PixelCanvas, Int, Int) -> Void
    private let texture: SKMutableTexture
    private let counter = FrameCounter()

    init(canvas size: WatchCanvas, draw: @escaping (PixelCanvas, Int, Int) -> Void) {
        canvas = PixelCanvas(width: size.width, height: size.height)
        self.draw = draw
        texture = SKMutableTexture(size: CGSize(width: size.width, height: size.height))
        texture.filteringMode = .nearest
        super.init(size: CGSize(width: size.width, height: size.height))
        scaleMode = .fill
        backgroundColor = .black
        let node = SKSpriteNode(texture: texture, size: self.size)
        node.position = CGPoint(x: self.size.width / 2, y: self.size.height / 2)
        addChild(node)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    override func update(_ currentTime: TimeInterval) {
        let fps = counter.tick(currentTime)
        draw(canvas, counter.frames, fps)
        let width = canvas.width, height = canvas.height, rowBytes = width * 4
        let src = UnsafeRawPointer(canvas.buffer)
        texture.modifyPixelData { raw, _ in
            guard let raw else { return }
            // Row 0 of the texture is the bottom row; the canvas is y down.
            for row in 0..<height {
                (raw + (height - 1 - row) * rowBytes).copyMemory(from: src + row * rowBytes, byteCount: rowBytes)
            }
        }
    }
}

/// Puts a blit view on the glass at exactly its pixel size, on the pixel grid, over black.
@MainActor
struct OnTheGlass<Content: View>: View {
    let content: Content
    private let glass = Glass.current

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            content
                .offset(x: glass.canvasOrigin.x, y: glass.canvasOrigin.y)
        }
        .frame(width: glass.pointSize.width, height: glass.pointSize.height, alignment: .topLeading)
        .ignoresSafeArea()
    }
}
