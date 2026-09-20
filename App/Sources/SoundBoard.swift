import AVFoundation
import UIKit

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
    // The rest of the organ (#17). The three longest buffers in the game: rendered off the main
    // thread the first time each is needed, never eagerly at launch like everything above.
    private var threeBlindMiceBuffer, funeralMarchBuffer, takeMeOutBuffer: AVAudioPCMBuffer?

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

    // MARK: - The rest of the organ (#17)

    /// Builds a buffer off the main thread. Free of `self`, so it is safe to call from
    /// `Task.detached`.
    private nonisolated static func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count)))!
        b.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { b.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return b
    }

    /// *Three Blind Mice*'s cue (#17): two called strikes in a row. No delay; the gap before the
    /// next windup is short. Rendered off the main thread the first time it is needed.
    func threeBlindMice() {
        guard !isMuted else { return }
        promptID += 1
        let id = promptID
        Task { @MainActor [weak self] in
            guard let self else { return }
            let buffer: AVAudioPCMBuffer
            if let cached = self.threeBlindMiceBuffer { buffer = cached }
            else {
                buffer = await Task.detached(priority: .utility) { Self.makeBuffer(Synth.threeBlindMice()) }.value
                self.threeBlindMiceBuffer = buffer
            }
            guard self.promptID == id else { return }         // the pitch beat us to it
            self.play(buffer, on: self.organ)
        }
    }

    /// Chopin's cue (#17): a home-run streak of 5+ just died. `streakOver` still plays for a
    /// streak of 3–4; this doesn't replace it. Rendered off the main thread on first use.
    func funeralMarch(after seconds: Double) {
        guard !isMuted else { return }
        promptID += 1
        let id = promptID
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.promptID == id else { return }
            let buffer: AVAudioPCMBuffer
            if let cached = self.funeralMarchBuffer { buffer = cached }
            else {
                buffer = await Task.detached(priority: .utility) { Self.makeBuffer(Synth.funeralMarch()) }.value
                self.funeralMarchBuffer = buffer
            }
            guard self.promptID == id else { return }
            self.play(buffer, on: self.organ)
        }
    }

    /// How long after the stats board opens its organ starts (#17).
    static let statsOrganDelay = 1.0

    /// Starts *Take Me Out to the Ball Game* over the stats board, after `statsOrganDelay` (#17).
    /// Loops once if the board is still up when it ends, then stops for good — `stopOrgan` (from
    /// `hideStats`) always wins, mid-note if need be, same as everywhere else the organ plays.
    func startStatsOrgan() {
        guard !isMuted else { return }
        promptID += 1
        let id = promptID
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.statsOrganDelay * 1_000_000_000))
            guard let self, self.promptID == id else { return }
            let buffer: AVAudioPCMBuffer
            if let cached = self.takeMeOutBuffer { buffer = cached }
            else {
                buffer = await Task.detached(priority: .utility) { Self.makeBuffer(Synth.takeMeOut()) }.value
                self.takeMeOutBuffer = buffer
            }
            guard self.promptID == id else { return }
            self.play(buffer, on: self.organ)
            try? await Task.sleep(nanoseconds: UInt64(Synth.takeMeOutSeconds * 1_000_000_000))
            guard self.promptID == id else { return }          // stats board was closed already
            self.play(buffer, on: self.organ)
        }
    }

    func landed() { play(groundBuffer) }
    func streakOver(after seconds: Double) { play(streakOverBuffer, after: seconds) }
    func calledUp() { play(calledUpBuffer, after: 0.5) }

    /// `size` 0…1: how far past the wall it is going to land.
    func homeRun(size: Double) {
        play(cheers[Int((max(0, min(1, size)) * Double(cheers.count - 1)).rounded())], on: crowd)
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
