import AVFoundation
import DerbyCore
import SpriteKit
import UIKit

/// Tuning knobs for the replay clip (#4, DESIGN.md §19).
struct ReplayClipRules {
    /// A clip is always drawn at the design size, never at the phone's canvas width, so a clip
    /// made on a Pro Max and one made on an SE are the same picture (DESIGN.md §8: the game is
    /// 320×224 with the wider phone showing more sky, which would make every clip a different
    /// crop). Both must be even for H.264.
    var canvasWidth = 320
    var canvasHeight = 224
    /// Whole-number upscale, nearest neighbour, no filtering — the same rule the `SKView` obeys.
    /// 320×224 × 4 = 1280×896.
    var scale = 4
    /// Frames a second, and the exact `dt` the machine is ticked at.
    var framesPerSecond: Int32 = 60
    /// Generous for flat colours, because the point is that one white frame and two hard cuts
    /// come out as themselves rather than as a smear.
    var bitrate = 12_000_000
    /// A stop, not a length: contact hold + flight ÷ 2 + a 1.30 s result is about four seconds,
    /// and nothing legitimate comes near this.
    var maxSeconds = 20.0
    /// Frames drawn between yields back to the run loop. The drawing lives in `SKScene`
    /// subclasses, so it runs on the main actor; yielding is what keeps the game playable while
    /// a clip is being made. One, because the total wall time is the same either way — the loop
    /// is yield-bound, not work-bound — and drawing three at a time only bunches the cost into
    /// hitches the player can feel. Measured in a Debug build: 3 dropped the game to 7 fps.
    var framesPerYield = 1
    /// v1 is the native landscape frame and nothing else. A square or vertical crop for TikTok
    /// and Reels is the open question in #4; the knob is here so the answer has somewhere to go.
    var crop = Crop.landscape
    enum Crop { case landscape }

    var pixelWidth: Int { canvasWidth * scale }
    var pixelHeight: Int { canvasHeight * scale }

    static let standard = ReplayClipRules()
}

enum ReplayClipError: Error {
    case writerUnavailable
    case noPixelBufferPool
    case nothingRendered
}

/// Re-renders a recorded home run off screen and writes it out as an H.264 `.mp4` (#4).
///
/// Nothing here draws anything. The frames come from the very same `AtBatScene.render(into:)`
/// and `WideScene.render(into:)` the player watched, called on off-screen copies of those scenes
/// against a machine `Replay` rebuilt from the record — which is the only reason the sky, the
/// clouds, the stands and the fireworks come out identical (DESIGN.md §17). The clip's beats are
/// §3's: the contact freeze, one white frame, the flight across both cameras, the landing number.
@MainActor
enum ReplayRenderer {

    /// Draws every frame and writes the file. Long-running but yielding, so the game behind it
    /// keeps its frame rate; the caller is expected to be a detached `Task`, not a tap handler.
    @discardableResult
    static func write(_ replay: Replay, to url: URL,
                      rules: ReplayClipRules = .standard) async throws -> URL {
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            throw ReplayClipError.writerUnavailable
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: rules.pixelWidth,
            AVVideoHeightKey: rules.pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: rules.bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                // No B-frames and a keyframe a second: a one-frame white flash between a dark
                // freeze and a bright field is exactly what frame reordering smears.
                AVVideoAllowFrameReorderingKey: false,
                AVVideoMaxKeyFrameIntervalKey: Int(rules.framesPerSecond),
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: rules.pixelWidth,
                kCVPixelBufferHeightKey as String: rules.pixelHeight,
            ])
        guard writer.canAdd(input) else { throw ReplayClipError.writerUnavailable }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ReplayClipError.writerUnavailable }
        writer.startSession(atSourceTime: .zero)

        var frames = 0
        do {
            frames = try await encodeFrames(replay, rules: rules, input: input, adaptor: adaptor)
        } catch {
            writer.cancelWriting()
            throw error
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
        guard frames > 0 else { throw ReplayClipError.nothingRendered }
        return url
    }

    /// The frame loop. Mirrors `CanvasScene.update(_:)` exactly — tick first, then draw — so the
    /// clip lands on the same frames the player saw. The cut is §3's: the tick that returns
    /// `.flash` and `.cutToWide` gives this one white frame, and the wide camera has the next.
    private static func encodeFrames(_ replay: Replay, rules: ReplayClipRules,
                                     input: AVAssetWriterInput,
                                     adaptor: AVAssetWriterInputPixelBufferAdaptor) async throws -> Int {
        var machine = Replay.machine(from: replay)

        let atBat = AtBatScene()
        let wide = WideScene()
        for scene in [atBat, wide] as [CanvasScene] {
            scene.isOffScreen = true
            scene.size = CGSize(width: rules.canvasWidth, height: rules.canvasHeight)
            scene.scaleMode = .aspectFit
            // A clip has no notch to dodge: the full design frame, every time.
            scene.safeLeft = 0
            scene.safeRight = 0
        }
        atBat.restoreContactVisual(from: replay)

        let canvas = PixelCanvas(width: rules.canvasWidth, height: rules.canvasHeight)
        var current: CanvasScene = atBat
        var pendingFlash = false
        var frame = 0
        let dt = 1.0 / Double(rules.framesPerSecond)
        let maxFrames = Int(rules.maxSeconds * Double(rules.framesPerSecond))

        while frame < maxFrames {
            let transitions = machine.tick(dt)
            var finished = false
            for transition in transitions {
                switch transition {
                case .flash: pendingFlash = true
                case .cutToWide: current = wide
                case .cutToAtBat: finished = true   // the result hold is over; the clip ends here
                default: break
                }
            }
            if finished { break }

            current.replayMachine = machine
            if pendingFlash {
                canvas.fill(Palette.chalk)
                pendingFlash = false
            } else {
                current.render(into: canvas)
            }

            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            try append(canvas, to: adaptor, at: frame, rules: rules)
            frame += 1
            if frame % rules.framesPerYield == 0 { await Task.yield() }
        }
        return frame
    }

    /// Scales the canvas up by a whole number with nearest neighbour — every design pixel becomes
    /// a hard `scale × scale` block, no interpolation anywhere — and hands it to the encoder.
    private static func append(_ canvas: PixelCanvas,
                               to adaptor: AVAssetWriterInputPixelBufferAdaptor,
                               at frame: Int, rules: ReplayClipRules) throws {
        guard let pool = adaptor.pixelBufferPool else { throw ReplayClipError.noPixelBufferPool }
        var maybeBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer) == kCVReturnSuccess,
              let buffer = maybeBuffer else { throw ReplayClipError.noPixelBufferPool }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let destination = base.assumingMemoryBound(to: UInt32.self)
            let destinationStride = CVPixelBufferGetBytesPerRow(buffer) / 4
            let scale = rules.scale
            let width = canvas.width
            for y in 0..<canvas.height {
                let sourceRow = canvas.buffer + y * width
                let rowStart = destination + y * scale * destinationStride
                var x = 0
                for i in 0..<width {
                    // `PixelCanvas` stores R,G,B,A in memory (`Palette.RGBA8.packed`); the buffer
                    // wants B,G,R,A. Swap the two ends once per design pixel, not per output one.
                    let p = sourceRow[i]
                    let bgra = (p & 0xFF00_FF00) | ((p & 0x00FF_0000) >> 16) | ((p & 0x0000_00FF) << 16)
                    for _ in 0..<scale {
                        rowStart[x] = bgra
                        x += 1
                    }
                }
                for row in 1..<scale {
                    (rowStart + row * destinationStride).update(from: rowStart, count: width * scale)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let time = CMTime(value: CMTimeValue(frame), timescale: rules.framesPerSecond)
        if !adaptor.append(buffer, withPresentationTime: time) {
            throw ReplayClipError.writerUnavailable
        }
    }
}

/// The system share sheet, and nothing around it: no menu, no confirmation, no toast (#4).
@MainActor
enum ReplayShare {
    static func present(_ url: URL, from view: UIView?) {
        guard let root = view?.window?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        guard !(top is UIActivityViewController) else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // An iPad has nowhere to hang a popover without a button, so it hangs off the middle.
        if let popover = sheet.popoverPresentationController, let view {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
    }
}
