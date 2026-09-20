import AVFoundation
import UIKit
import DerbyCore

/// Plays `Synth`'s sounds. Everything is rendered into buffers once at launch and fired as
/// one-shots through a small pool of player nodes, so a sound costs nothing at the moment it is
/// needed.
///
/// The session is `.ambient`: the ring/silent switch mutes the game, and the player's own music
/// or podcast keeps playing underneath. A game you play one-handed somewhere quiet must never be
/// the thing that makes noise by surprise.
@MainActor
final class SoundBoard {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!
    private let voices = (0..<5).map { _ in AVAudioPlayerNode() }
    /// The crowd has its own node so a new reaction replaces the last one instead of piling on.
    private let crowd = AVAudioPlayerNode()
    /// The organ has its own node too, so the pitch can cut it off mid-note, as a real organist
    /// stops dead when the pitcher comes set.
    private let organ = AVAudioPlayerNode()
    /// Bumped whenever the organ starts or is cut, so a crowd answer never follows a cut prompt.
    private var promptID = 0
    private var nextVoice = 0
    private var observers: [NSObjectProtocol] = []

    /// `-mute`: no sound at all (simulator runs, screenshots).
    private let isMuted = ProcessInfo.processInfo.arguments.contains("-mute")

    private let cracks: [AVAudioPCMBuffer]
    private let cheers: [AVAudioPCMBuffer]
    private let whiffBuffer, strikeBuffer, ballBuffer, groanBuffer: AVAudioPCMBuffer
    private let wallBuffer, groundBuffer, streakOverBuffer, calledUpBuffer: AVAudioPCMBuffer
    private let wompBuffer, chargeRunBuffer, shoutBuffer: AVAudioPCMBuffer

    init() {
        let format = self.format
        func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
            let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count)))!
            b.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
            return b
        }
        cracks = (0...8).map { buffer(Synth.crack(strength: Double($0) / 8)) }
        cheers = (0...4).map { buffer(Synth.cheer(size: Double($0) / 4)) }
        whiffBuffer = buffer(Synth.whiff())
        strikeBuffer = buffer(Synth.umpStrike())
        ballBuffer = buffer(Synth.umpBall())
        groanBuffer = buffer(Synth.groan())
        wallBuffer = buffer(Synth.thump(deep: false))
        groundBuffer = buffer(Synth.thump(deep: true))
        streakOverBuffer = buffer(Synth.streakOver())
        calledUpBuffer = buffer(Synth.calledUp())
        wompBuffer = buffer(Synth.wompWomp())
        chargeRunBuffer = buffer(Synth.chargeRun())
        shoutBuffer = buffer(Synth.crowdShout())

        guard !isMuted else { return }
        for node in voices + [crowd, organ] {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        start()

        // The engine stops on its own when the route changes (headphones in or out), when a call
        // or Siri interrupts, and often across a trip to the background. Bring it back each time.
        let center = NotificationCenter.default
        for name in [Notification.Name.AVAudioEngineConfigurationChange,
                     AVAudioSession.interruptionNotification,
                     UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.start() }
            })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func start() {
        guard !isMuted, !engine.isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient)
        try? session.setActive(true)
        engine.prepare()
        try? engine.start()
    }

    private func play(_ buffer: AVAudioPCMBuffer, on node: AVAudioPlayerNode? = nil, after seconds: Double = 0) {
        guard !isMuted else { return }
        if seconds > 0 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self?.play(buffer, on: node)
            }
            return
        }
        start()
        guard engine.isRunning else { return }
        let voice = node ?? voices[nextVoice]
        if node == nil { nextVoice = (nextVoice + 1) % voices.count }
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !voice.isPlaying { voice.play() }
    }

    // MARK: - The sounds, by what happened

    /// `strength` 0…1: how well the ball was hit.
    func crack(strength: Double) {
        play(cracks[Int((max(0, min(1, strength)) * Double(cracks.count - 1)).rounded())])
    }

    func whiff() { play(whiffBuffer) }
    func calledStrike() { play(strikeBuffer) }
    func calledBall() { play(ballBuffer) }
    /// The thump, the crowd's *ohh*, and then the trombone has its say.
    func offTheWall() {
        play(wallBuffer)
        play(groanBuffer, on: crowd, after: 0.08)
        play(wompBuffer, after: 0.22)
    }

    /// The organ runs up the scale and the crowd answers. If the pitch cuts the organ off first,
    /// nobody answers.
    func chargePrompt() {
        promptID += 1
        let id = promptID
        play(chargeRunBuffer, on: organ)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Synth.chargeRunSeconds * 1_000_000_000))
            guard let self, self.promptID == id else { return }
            self.play(self.shoutBuffer)
        }
    }

    /// The pitcher is set: the organ stops, mid-note. No fade, ever.
    func stopOrgan() {
        promptID += 1
        if organ.isPlaying { organ.stop() }
    }
    func landed() { play(groundBuffer) }
    func streakOver(after seconds: Double) { play(streakOverBuffer, after: seconds) }
    func calledUp() { play(calledUpBuffer, after: 0.5) }

    /// `size` 0…1: how far past the wall it is going to land.
    func homeRun(size: Double) {
        play(cheers[Int((max(0, min(1, size)) * Double(cheers.count - 1)).rounded())], on: crowd)
    }

    // MARK: - Fireworks (issue #14, "life": fireworks, sky and backdrops)

    /// Built the first time a streak earns a show, not at launch: fireworks are rare, so there
    /// is no reason every player pays to render one up front.
    private lazy var fireworkPopBuffer: AVAudioPCMBuffer = makeBuffer(Synth.fireworkPop())

    /// Mirrors the local `buffer(_:)` helper inside `init()`, for a buffer built lazily instead.
    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count)))!
        b.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return b
    }

    /// A soft pop per shell, mixed under the cheer that `homeRun(size:)` already started from
    /// the same `.clearedWall` transition. Timed to each shell's burst, not its launch, so the
    /// sound lands with the particles, not the streak of light climbing to them.
    func fireworks(_ show: FireworksShow, rules: FireworksRules) {
        for shell in 0..<show.shellCount {
            play(fireworkPopBuffer, after: Double(shell) * rules.shellLaunchInterval + rules.risePeriod)
        }
    }
}

/// The three things worth feeling (DESIGN.md §11): contact, the wall, a home run.
@MainActor
final class Haptics {
    private let bat = UIImpactFeedbackGenerator(style: .rigid)
    private let wall = UIImpactFeedbackGenerator(style: .heavy)
    private let notice = UINotificationFeedbackGenerator()

    /// Call as the pitch is thrown, so the Taptic Engine is awake when the bat arrives.
    func prepare() { bat.prepare() }

    func contact(strength: Double) { bat.impactOccurred(intensity: 0.45 + 0.55 * max(0, min(1, strength))) }
    func offTheWall() { wall.impactOccurred(intensity: 0.8) }
    func homeRun() { notice.notificationOccurred(.success) }
}
