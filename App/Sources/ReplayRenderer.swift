import AVFoundation
import DerbyCore
import QuartzCore
import SpriteKit
import UIKit

/// Tuning knobs for the replay clip (#4, #42, DESIGN.md §19).
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
    /// A stop, not a length: the lead-in + contact hold + flight ÷ 2 + a 1.30 s result is about
    /// four and a half seconds, and nothing legitimate comes near this.
    var maxSeconds = 20.0
    /// Frames drawn between yields back to the run loop. One, and the measurement says so rather
    /// than the other way round: a yield costs **0.008–0.054 ms** in a Release build, and letting
    /// go of the main thread is what lets the encoder drain. Holding it for 100 ms at a time
    /// instead took the same clip from 3.2 s to 12.4 s, all of it spent waiting on an encoder
    /// that had been starved. The #42 pull request has the table.
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

/// Where a clip's time went, in milliseconds a frame (#42). Dwight, from an iPad mini 6: "its
/// VEEERRRRYYY slow to export on my ipad mini 6." This is the instrument that answers why, on
/// whatever machine is asking — it costs about a tenth of a microsecond a frame to keep.
struct ReplayRenderMetrics {
    var frames = 0
    /// The two scenes' own `render(into:)`: one whole software frame at 320×224.
    var renderSeconds = 0.0
    /// Taking a buffer out of the adaptor's pool and locking it.
    var bufferSeconds = 0.0
    /// The nearest-neighbour upscale and the BGRA fill into that buffer.
    var upscaleSeconds = 0.0
    /// `AVAssetWriterInputPixelBufferAdaptor.append`.
    var appendSeconds = 0.0
    /// Waiting because the encoder said it had had enough for now.
    var waitSeconds = 0.0
    /// Letting go of the main thread so the screen behind can repaint.
    var yieldSeconds = 0.0
    /// Start to finished file, including the writer's own `finishWriting`.
    var totalSeconds = 0.0

    private func ms(_ seconds: Double) -> String {
        String(format: "%.3f", frames > 0 ? seconds * 1000 / Double(frames) : 0)
    }

    /// One line per stage, in milliseconds a frame, plus the wall time and what it bought.
    var summary: String {
        let seconds = Double(frames) / 60
        return """
        REPLAY CLIP \(frames) frames (\(String(format: "%.2f", seconds)) s of video) \
        in \(String(format: "%.3f", totalSeconds)) s wall \
        (\(String(format: "%.2f", totalSeconds / max(0.001, seconds)))× its own length)
          render   \(ms(renderSeconds)) ms/frame
          buffer   \(ms(bufferSeconds)) ms/frame
          upscale  \(ms(upscaleSeconds)) ms/frame
          append   \(ms(appendSeconds)) ms/frame
          wait     \(ms(waitSeconds)) ms/frame
          yield    \(ms(yieldSeconds)) ms/frame
        """
    }
}

struct ReplayClipResult {
    let url: URL
    let metrics: ReplayRenderMetrics
}

/// Re-renders a recorded swing off screen and writes it out as an H.264 `.mp4` (#4, #42).
///
/// Nothing here draws anything and nothing here decides what a replay looks like: `ReplayPlayback`
/// does both, and the replay screen drives the very same object in real time. So the file and the
/// thing the player watched before asking for it cannot disagree.
///
/// This only ever runs when `SHARE` is tapped on the replay screen, with the game paused behind
/// it. It no longer runs behind a live game at all — that was #42's second complaint, and it is
/// gone by construction rather than by being made cheaper.
@MainActor
enum ReplayRenderer {

    /// Draws every frame and writes the file.
    @discardableResult
    static func write(_ replay: Replay, to url: URL,
                      rules: ReplayClipRules = .standard,
                      replayRules: ReplayRules = .standard) async throws -> ReplayClipResult {
        let started = CACurrentMediaTime()
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
        // Not a camera: the encoder is fed as fast as it will take frames, never on a clock.
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

        var metrics = ReplayRenderMetrics()
        do {
            try await encodeFrames(replay, rules: rules, replayRules: replayRules,
                                   writer: writer, input: input, adaptor: adaptor,
                                   metrics: &metrics)
        } catch {
            writer.cancelWriting()
            throw error
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let error = writer.error { throw error }
        guard metrics.frames > 0 else { throw ReplayClipError.nothingRendered }
        metrics.totalSeconds = CACurrentMediaTime() - started
        #if DEBUG
        print(metrics.summary)
        #endif
        return ReplayClipResult(url: url, metrics: metrics)
    }

    /// The frame loop. `ReplayPlayback` owns the beats, the cuts and the white frame; this owns
    /// the clock, the pixels and the encoder.
    private static func encodeFrames(_ replay: Replay, rules: ReplayClipRules,
                                     replayRules: ReplayRules,
                                     writer: AVAssetWriter,
                                     input: AVAssetWriterInput,
                                     adaptor: AVAssetWriterInputPixelBufferAdaptor,
                                     metrics: inout ReplayRenderMetrics) async throws {
        let playback = ReplayPlayback(replay, rules: replayRules)
        // A clip has no notch to dodge and no phone to be as wide as: the full design frame,
        // every time, so a clip made on any device is the same picture.
        playback.resize(width: rules.canvasWidth, height: rules.canvasHeight,
                        safeLeft: 0, safeRight: 0)

        let canvas = PixelCanvas(width: rules.canvasWidth, height: rules.canvasHeight)
        let dt = 1.0 / Double(rules.framesPerSecond)
        let maxFrames = Int(rules.maxSeconds * Double(rules.framesPerSecond))

        while metrics.frames < maxFrames {
            playback.advance(dt)
            if playback.isFinished { break }

            var mark = CACurrentMediaTime()
            playback.render(into: canvas)
            metrics.renderSeconds += CACurrentMediaTime() - mark

            // Yield rather than sleep while the encoder has had enough for now: a sleep holds
            // the main thread's turn and the encoder only falls further behind, which is what
            // the 31.8 ms/frame in the #42 table is. A yield gives the turn up and comes back.
            while !input.isReadyForMoreMediaData {
                // A writer that has given up never becomes ready again, and this loop is a spin:
                // without the guard a failed export would be a hot hang rather than an error.
                guard writer.status == .writing else {
                    throw writer.error ?? ReplayClipError.writerUnavailable
                }
                mark = CACurrentMediaTime()
                await Task.yield()
                metrics.waitSeconds += CACurrentMediaTime() - mark
            }
            try append(canvas, to: adaptor, at: metrics.frames, rules: rules, metrics: &metrics)
            metrics.frames += 1

            if metrics.frames % max(1, rules.framesPerYield) == 0 {
                mark = CACurrentMediaTime()
                await Task.yield()
                metrics.yieldSeconds += CACurrentMediaTime() - mark
            }
        }
    }

    /// Scales the canvas up by a whole number with nearest neighbour — every design pixel becomes
    /// a hard `scale × scale` block, no interpolation anywhere — and hands it to the encoder.
    ///
    /// One row is filled by runs and then copied down `scale - 1` times, so the whole upscale is
    /// bulk memory calls and no per-output-pixel work at all. The runs are the point: this art is
    /// one palette line with no gradients and no anti-aliasing (DESIGN.md §9), so a row of sky is
    /// a single run 320 wide and even a busy row is a few dozen. A `memset_pattern4` per run
    /// costs one C call; a `UnsafeMutablePointer` subscript per output pixel costs 286,720
    /// unspecialised generic accesses, which measured **37.5 ms a frame** in a Debug build.
    /// Nothing is allocated per frame — the buffer comes from the adaptor's own pool.
    private static func append(_ canvas: PixelCanvas,
                               to adaptor: AVAssetWriterInputPixelBufferAdaptor,
                               at frame: Int, rules: ReplayClipRules,
                               metrics: inout ReplayRenderMetrics) throws {
        var mark = CACurrentMediaTime()
        guard let pool = adaptor.pixelBufferPool else { throw ReplayClipError.noPixelBufferPool }
        var maybeBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer) == kCVReturnSuccess,
              let buffer = maybeBuffer else { throw ReplayClipError.noPixelBufferPool }
        CVPixelBufferLockBaseAddress(buffer, [])
        metrics.bufferSeconds += CACurrentMediaTime() - mark

        mark = CACurrentMediaTime()
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            let scale = rules.scale
            let width = canvas.width
            let rowBytes = width * scale * 4
            for y in 0..<canvas.height {
                let sourceRow = canvas.buffer + y * width
                let rowStart = base + y * scale * stride
                var i = 0
                while i < width {
                    let p = sourceRow[i]
                    var run = i + 1
                    while run < width, sourceRow[run] == p { run += 1 }
                    // `PixelCanvas` stores R,G,B,A in memory (`Palette.RGBA8.packed`); the buffer
                    // wants B,G,R,A. Swap the two ends once per run, not once per output pixel.
                    var bgra = (p & 0xFF00_FF00) | ((p & 0x00FF_0000) >> 16) | ((p & 0x0000_00FF) << 16)
                    memset_pattern4(rowStart + i * scale * 4, &bgra, (run - i) * scale * 4)
                    i = run
                }
                for row in 1..<scale {
                    (rowStart + row * stride).copyMemory(from: rowStart, byteCount: rowBytes)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        metrics.upscaleSeconds += CACurrentMediaTime() - mark

        mark = CACurrentMediaTime()
        let time = CMTime(value: CMTimeValue(frame), timescale: rules.framesPerSecond)
        let appended = adaptor.append(buffer, withPresentationTime: time)
        metrics.appendSeconds += CACurrentMediaTime() - mark
        if !appended { throw ReplayClipError.writerUnavailable }
    }
}

/// The system share sheet, and nothing around it: no menu, no confirmation, no toast (#4).
///
/// One sheet does both jobs Dwight asked for — "they can save and share from there" — because its
/// own first row is *Save Video*. A separate `SAVE` of our own would mean a photo-library
/// permission prompt, an Info.plist key and a failure path this game has no way to speak about.
/// Decision, Claude's, 2026-09-20, unreviewed (DESIGN.md §19).
@MainActor
enum ReplayShare {
    static func present(_ url: URL, from view: UIView?, anchor: CGRect? = nil) {
        guard let root = view?.window?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        guard !(top is UIActivityViewController) else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // An iPad has no sheet without an anchor, and this game runs on one: Dwight plays on an
        // iPad mini 6. The anchor is the word that was tapped, so the popover points at it.
        if let popover = sheet.popoverPresentationController, let view {
            popover.sourceView = view
            popover.sourceRect = anchor
                ?? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            // The word is in the top corner, so the sheet hangs below it with the arrow on top.
            popover.permittedArrowDirections = anchor == nil ? [] : [.up]
        }
        top.present(sheet, animated: true)
    }
}
