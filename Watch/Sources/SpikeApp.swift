import AVFoundation
import SwiftUI
import WatchKit

/// W0 (docs/watch.md §9): a throwaway spike that measures the glass, the finger, the speaker, the
/// haptics and the battery, so the guessed numbers in docs/watch.md can be replaced with measured
/// ones. Not the game, and not shipped: a watch-only app with its own bundle id, so the phone
/// app's build never sees it. `Watch/README.md` says what to do with each page.
///
/// It is the one place in this project with a menu, because it is not the game.
@main
struct SpikeApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    NavigationLink("1 Pattern (image)") { PatternPage(sprite: false) }
                    NavigationLink("2 Pattern (sprite)") { PatternPage(sprite: true) }
                    NavigationLink("3 Drag") { DragPage() }
                    NavigationLink("4 Haptics") { HapticsPage() }
                    NavigationLink("5 Sound") { SoundPage() }
                    NavigationLink("6 Battery") { BatteryPage() }
                    NavigationLink("7 Info + log") { InfoPage() }
                }
                .navigationTitle("W0")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // How the wrist going down looks from here (§5): the phase changes, in order.
            SpikeLog.shared.add("scenePhase \(phase)")
        }
    }
}

/// Everything the spike measures, on the glass (Info page) and in Xcode's console.
@MainActor
final class SpikeLog: ObservableObject {
    static let shared = SpikeLog()
    @Published private(set) var lines: [String] = []
    private let start = Date()

    func add(_ line: String) {
        let t = String(format: "%7.2f", Date().timeIntervalSince(start))
        let stamped = "\(t) \(line)"
        print("W0 \(stamped)")
        lines.append(stamped)
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
    }
}

// MARK: - 1, 2: the test pattern, through each blit path

/// Full screen, nothing over it. A tap leaves.
@MainActor
struct PatternPage: View {
    let sprite: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let glass = Glass.current
        let draw: (PixelCanvas, Int, Int) -> Void = { c, frame, fps in
            TestPattern.draw(into: c, canvas: glass.canvas, frame: frame,
                             label: "\(sprite ? "SK" : "CG") \(fps) FPS")
        }
        OnTheGlass {
            if sprite { SpriteBlitView(draw: draw) } else { ImageBlitView(draw: draw) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onTapGesture { dismiss() }
        .onAppear {
            SpikeLog.shared.add("pattern \(sprite ? "sprite" : "image") on: \(glass.pixelWidth)x\(glass.pixelHeight) px, "
                                + "canvas \(glass.canvas.width)x\(glass.canvas.height) at \(glass.canvas.scale)")
        }
    }
}

// MARK: - 3: the finger

/// Slice across the glass. Each stroke reports how often the gesture sampled, how long and how
/// fast it was in design units — the numbers `WatchSliceRules` guesses at (§5).
@MainActor
struct DragPage: View {
    @State private var times: [Date] = []
    @State private var points: [CGPoint] = []
    @State private var report = "Slice across the glass"
    private let glass = Glass.current

    /// Points to design units at the canvas's scale.
    private var unitsPerPoint: Double { Double(glass.screenScale) / Double(glass.canvas.scale) }

    var body: some View {
        ZStack {
            Color.black
            Canvas { ctx, _ in
                var path = Path()
                path.addLines(points)
                ctx.stroke(path, with: .color(.yellow), lineWidth: 1)
                for p in points { ctx.fill(Path(CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)), with: .color(.red)) }
            }
            Text(report).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white)
                .multilineTextAlignment(.leading).frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    if times.isEmpty { points = [] }
                    times.append(v.time)
                    points.append(v.location)
                }
                .onEnded { v in
                    times.append(v.time)
                    points.append(v.location)
                    summarise()
                    times = []
                }
        )
    }

    private func summarise() {
        guard times.count > 1, let first = times.first, let last = times.last else { return }
        let gaps = zip(times.dropFirst(), times).map { $0.timeIntervalSince($1) * 1000 }.sorted()
        let duration = last.timeIntervalSince(first)
        let u = unitsPerPoint
        let length = zip(points.dropFirst(), points).reduce(0.0) {
            $0 + Double(hypot($1.0.x - $1.1.x, $1.0.y - $1.1.y))
        } * u
        // Peak speed over any ~80 ms window, the window `AtBatScene` measures the finger over.
        var peak = 0.0
        for j in points.indices {
            var i = j
            while i > 0, times[j].timeIntervalSince(times[i - 1]) < 0.08 { i -= 1 }
            let dt = times[j].timeIntervalSince(times[i])
            if dt >= 0.016 {
                let d = Double(hypot(points[j].x - points[i].x, points[j].y - points[i].y))
                peak = max(peak, d * u / dt)
            }
        }
        let hz = Double(times.count - 1) / max(duration, 0.001)
        report = String(format: "%d samples %.0f Hz\ngap min %.0f med %.0f max %.0f ms\n%.0f u in %.0f ms\npeak %.0f u/s",
                        times.count, hz, gaps.first ?? 0, gaps[gaps.count / 2], gaps.last ?? 0,
                        length, duration * 1000, peak)
        SpikeLog.shared.add("drag " + report.replacingOccurrences(of: "\n", with: " | "))
    }
}

// MARK: - 4: haptics

/// Every canned haptic, felt one at a time. Note which ones also sound a tone with the watch
/// not silenced (§6's known trap).
@MainActor
struct HapticsPage: View {
    private static let named: [(String, WKHapticType)] = [
        ("notification", .notification), ("directionUp", .directionUp),
        ("directionDown", .directionDown), ("success", .success), ("failure", .failure),
        ("retry", .retry), ("start", .start), ("stop", .stop), ("click", .click),
    ]

    var body: some View {
        List {
            ForEach(Self.named.indices, id: \.self) { i in
                let (name, type) = Self.named[i]
                Button(name) {
                    WKInterfaceDevice.current().play(type)
                    SpikeLog.shared.add("haptic \(name)")
                }
            }
            // Anything newer than the nine above, by number: whatever this watchOS has.
            ForEach(9..<14, id: \.self) { raw in
                Button("raw \(raw)") {
                    if let type = WKHapticType(rawValue: raw) { WKInterfaceDevice.current().play(type) }
                    SpikeLog.shared.add("haptic raw \(raw)")
                }
            }
        }
        .navigationTitle("Haptics")
    }
}

// MARK: - 5: sound

/// One barrelled crack through the speaker, under two audio-session categories, with the time it
/// took to render and start. Try each with the watch silenced and not.
@MainActor
struct SoundPage: View {
    @State private var engine = AVAudioEngine()
    @State private var player = AVAudioPlayerNode()
    @State private var attached = false
    @State private var report = ""

    var body: some View {
        List {
            Button("crack · ambient") { play(.ambient) }
            Button("crack · playback") { play(.playback) }
            Text(report).font(.system(size: 11, design: .monospaced))
        }
        .navigationTitle("Sound")
    }

    private func play(_ category: AVAudioSession.Category) {
        let t0 = Date()
        let samples = Synth.crack(strength: 1)
        let rendered = Date().timeIntervalSince(t0) * 1000
        let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(category)
            try session.setActive(true)
            if !attached {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                attached = true
            }
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !player.isPlaying { player.play() }
            report = String(format: "%@: render %.0f ms, started %.0f ms", category.rawValue, rendered,
                            Date().timeIntervalSince(t0) * 1000)
        } catch {
            report = "\(category.rawValue): \(error.localizedDescription)"
        }
        SpikeLog.shared.add("sound \(report)")
    }
}

// MARK: - 6: battery

/// Five minutes at the game's frame rate through the image path, with the battery read at the
/// start and now. Keep the wrist up: the watch stops drawing when it goes down.
@MainActor
struct BatteryPage: View {
    @State private var started: Date?
    @State private var startLevel: Float = 0
    @State private var sprite = false
    private let device = WKInterfaceDevice.current()

    var body: some View {
        let glass = Glass.current
        if let started {
            let device = self.device
            let startLevel = self.startLevel
            OnTheGlass {
                let draw: (PixelCanvas, Int, Int) -> Void = { c, frame, fps in
                    TestPattern.draw(into: c, canvas: glass.canvas, frame: frame, label: "\(fps) FPS")
                    let secs = Int(Date().timeIntervalSince(started))
                    let now = Int((device.batteryLevel * 100).rounded())
                    let line = String(format: "%d:%02d %d%%-%d%%", secs / 60, secs % 60,
                                      Int((startLevel * 100).rounded()), now)
                    TestPattern.label3(c, line, y: 20, Palette.chalk)
                }
                if sprite { SpriteBlitView(draw: draw) } else { ImageBlitView(draw: draw) }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onTapGesture { stop() }
        } else {
            List {
                Button("Start · image") { start(sprite: false) }
                Button("Start · sprite") { start(sprite: true) }
                Text("Tap the running screen to stop.").font(.footnote)
            }
            .navigationTitle("Battery")
        }
    }

    private func start(sprite: Bool) {
        device.isBatteryMonitoringEnabled = true
        startLevel = device.batteryLevel
        self.sprite = sprite
        started = Date()
        SpikeLog.shared.add("battery start \(sprite ? "sprite" : "image") at \(startLevel)")
    }

    private func stop() {
        let secs = started.map { Date().timeIntervalSince($0) } ?? 0
        SpikeLog.shared.add(String(format: "battery stop after %.0f s: %.3f -> %.3f", secs,
                                   startLevel, device.batteryLevel))
        started = nil
    }
}

// MARK: - 7: what this watch says about itself

@MainActor
struct InfoPage: View {
    @ObservedObject private var log = SpikeLog.shared
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let d = WKInterfaceDevice.current()
        let g = Glass.current
        GeometryReader { geo in
            List {
                Section("Device") {
                    row("model", d.model)
                    row("watchOS", d.systemVersion)
                    row("points", "\(fmt(g.pointSize.width))x\(fmt(g.pointSize.height)) @\(fmt(g.screenScale))")
                    row("pixels", "\(g.pixelWidth)x\(g.pixelHeight)")
                    row("canvas", "\(g.canvas.width)x\(g.canvas.height) x\(g.canvas.scale)")
                    row("origin", "\(g.canvas.originX),\(g.canvas.originY) px")
                    row("safe", "t\(fmt(geo.safeAreaInsets.top)) l\(fmt(geo.safeAreaInsets.leading)) "
                        + "b\(fmt(geo.safeAreaInsets.bottom)) r\(fmt(geo.safeAreaInsets.trailing))")
                    row("wrist", d.wristLocation == .left ? "left" : "right")
                    row("crown", d.crownOrientation == .left ? "left" : "right")
                    row("lum. reduced", isLuminanceReduced ? "yes" : "no")
                }
                Section("Log") {
                    ForEach(log.lines.indices.reversed(), id: \.self) { i in
                        Text(log.lines[i]).font(.system(size: 10, design: .monospaced))
                    }
                }
            }
        }
        .navigationTitle("Info")
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).font(.system(size: 12, design: .monospaced)) }
    }

    private func fmt(_ x: CGFloat) -> String { String(format: "%.1f", Double(x)) }
}
