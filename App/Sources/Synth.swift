import Foundation

/// Every sound in the game, as arithmetic. No audio files: a noise source, a few oscillators and
/// a few filters, in the spirit of a console that had an FM chip and a noise channel (DESIGN.md
/// §11). Placeholders by design, to be replaced one at a time if something better comes along.
/// All functions are pure and return mono samples in −1…1 at `sampleRate`.
enum Synth {
    static let sampleRate = 44_100.0

    // MARK: - Parts

    /// xorshift white noise. Seeded, so a sound is the same every launch.
    struct Noise {
        var state: UInt32
        init(seed: UInt32 = 0x9E37_79B9) { state = seed == 0 ? 1 : seed }
        mutating func next() -> Double {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return Double(state) / Double(UInt32.max) * 2 - 1
        }
    }

    /// RBJ cookbook biquad, transposed direct form II.
    struct Biquad {
        private let b0, b1, b2, a1, a2: Double
        private var z1 = 0.0, z2 = 0.0

        private init(_ b0: Double, _ b1: Double, _ b2: Double, _ a0: Double, _ a1: Double, _ a2: Double) {
            self.b0 = b0 / a0; self.b1 = b1 / a0; self.b2 = b2 / a0; self.a1 = a1 / a0; self.a2 = a2 / a0
        }

        static func bandpass(_ hz: Double, q: Double) -> Biquad {
            let w = 2 * Double.pi * hz / sampleRate, alpha = sin(w) / (2 * q)
            return Biquad(alpha, 0, -alpha, 1 + alpha, -2 * cos(w), 1 - alpha)
        }

        static func lowpass(_ hz: Double, q: Double = 0.707) -> Biquad {
            let w = 2 * Double.pi * hz / sampleRate, alpha = sin(w) / (2 * q), c = cos(w)
            return Biquad((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha)
        }

        static func highpass(_ hz: Double, q: Double = 0.707) -> Biquad {
            let w = 2 * Double.pi * hz / sampleRate, alpha = sin(w) / (2 * q), c = cos(w)
            return Biquad((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha)
        }

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    private static func count(_ seconds: Double) -> Int { Int(seconds * sampleRate) }

    /// Soft clip and scale, so stacked parts never wrap.
    private static func finish(_ samples: [Double], gain: Double) -> [Float] {
        samples.map { Float(tanh($0 * 1.4) * gain) }
    }

    // MARK: - The bat

    /// Bat on ball. `strength` 0…1 is how well it was hit: a weak one is a dull low *tock*, a
    /// barrelled one is a bright crack with the park's slap coming back off the stands.
    static func crack(strength s: Double) -> [Float] {
        let n = count(0.30)
        var out = [Double](repeating: 0, count: n)
        var noise = Noise(seed: 0x0BA7_0000 &+ UInt32(s * 1000))
        var edge = Biquad.highpass(900 + 2_800 * s)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let click = edge.process(noise.next()) * exp(-t / (0.009 + 0.020 * s)) * (0.5 + 0.4 * s)
            let hz = (240 + 840 * s) * (0.35 + 0.65 * exp(-t / 0.016))       // the pitch drops as it rings
            phase += 2 * Double.pi * hz / sampleRate
            let knock = sin(phase) * exp(-t / (0.020 + 0.022 * s)) * 0.85
            out[i] = click + knock
        }
        var stands = Biquad.lowpass(1_700)
        let delay = count(0.085)
        for i in delay..<n { out[i] += stands.process(out[i - delay]) * (0.10 + 0.24 * s) }
        return finish(out, gain: 0.5 + 0.45 * s)
    }

    /// A swing through air.
    static func whiff() -> [Float] {
        let dur = 0.20, n = count(dur)
        var noise = Noise(seed: 0x5717_F00D)
        var out = [Double](repeating: 0, count: n)
        var low = 0.0
        for i in 0..<n {
            let p = Double(i) / Double(n)
            // One-pole band that slides down as the bat goes by.
            let k = 0.35 - 0.27 * p
            low += k * (noise.next() - low)
            out[i] = low * pow(sin(Double.pi * p), 2)
        }
        return finish(out, gain: 0.30)
    }

    // MARK: - The umpire

    private struct Formant { let hz: Double, q: Double, gain: Double }

    /// One syllable of a voice: a buzzy source through a few resonances.
    private static func syllable(_ dur: Double, from f0: Double, to f1: Double, growl: Double, breath: Double,
                                 seed: UInt32, formants: [Formant]) -> [Double] {
        let n = count(dur)
        var filters = formants.map { Biquad.bandpass($0.hz, q: $0.q) }
        var noise = Noise(seed: seed)
        var phase = 0.0
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate, p = t / dur
            let hz = f0 + (f1 - f0) * p
            phase += hz / sampleRate
            let saw = 2 * (phase - phase.rounded(.down)) - 1
            let rough = 1 - growl + growl * (0.5 + 0.5 * sin(2 * Double.pi * 31 * t))
            let source = (saw + breath * noise.next()) * rough
            var voiced = 0.0
            for k in filters.indices { voiced += filters[k].process(source) * formants[k].gain }
            let attack = min(1, t / 0.012), release = min(1, (dur - t) / 0.05)
            out[i] = voiced * attack * release
        }
        return out
    }

    /// The call on a taken strike: a two-beat bark, *HEE-YAH*.
    static func umpStrike() -> [Float] {
        let hee = syllable(0.085, from: 170, to: 190, growl: 0.25, breath: 0.35, seed: 0x5781_0001,
                           formants: [Formant(hz: 330, q: 5, gain: 1), Formant(hz: 2_250, q: 7, gain: 0.7)])
        let yah = syllable(0.27, from: 195, to: 105, growl: 0.5, breath: 0.3, seed: 0x5781_0002,
                           formants: [Formant(hz: 760, q: 4, gain: 1), Formant(hz: 1_220, q: 5, gain: 0.8),
                                      Formant(hz: 2_500, q: 7, gain: 0.3)])
        return finish(hee + [Double](repeating: 0, count: count(0.03)) + yah, gain: 0.8)
    }

    /// The call on a taken ball: one low, short, unimpressed grunt.
    static func umpBall() -> [Float] {
        finish(syllable(0.16, from: 122, to: 98, growl: 0.3, breath: 0.25, seed: 0xBA11_0001,
                        formants: [Formant(hz: 420, q: 4, gain: 1), Formant(hz: 980, q: 5, gain: 0.5)]), gain: 0.5)
    }

    // MARK: - The crowd

    /// A few thousand people finding out at once. `size` 0…1: a wall-scraper gets a cheer, a
    /// no-doubter gets a longer, louder one with whistles in it.
    static func cheer(size: Double) -> [Float] {
        let dur = 1.8 + 1.5 * size, n = count(dur)
        var noise = Noise(seed: 0xC40D_0000 &+ UInt32(size * 100))
        var body = Biquad.bandpass(880, q: 0.7), air = Biquad.bandpass(2_400, q: 0.9)
        var out = [Double](repeating: 0, count: n)
        let hold = dur * 0.42, tail = 0.45 + 0.55 * size
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let x = noise.next()
            let roar = body.process(x) + 0.6 * air.process(x)
            let rise = min(1, t / 0.22), swell = rise * rise * (3 - 2 * rise)
            let fall = t < hold ? 1 : exp(-(t - hold) / tail)
            let flutter = 1 + 0.22 * sin(2 * Double.pi * 5.3 * t) + 0.13 * sin(2 * Double.pi * 8.1 * t + 1)
            out[i] = roar * swell * fall * flutter
        }
        // Whistles: short upward glides, more of them the bigger the hit.
        for w in 0..<Int((size * 4).rounded()) {
            let start = count(0.25 + 0.3 * Double(w)), length = count(0.22)
            var phase = 0.0
            for j in 0..<length where start + j < n {
                let p = Double(j) / Double(length)
                phase += 2 * Double.pi * (1_500 + 300 * Double(w) + 900 * p) / sampleRate
                out[start + j] += sin(phase) * pow(sin(Double.pi * p), 2) * 0.10
            }
        }
        return finish(out, gain: 0.32 + 0.42 * size)
    }

    /// Off the wall: the same people, let down. A short low *ohh*.
    static func groan() -> [Float] {
        let n = count(0.95)
        var noise = Noise(seed: 0x0440_0001)
        var low = Biquad.bandpass(500, q: 1.3), mid = Biquad.bandpass(930, q: 1.1)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let p = Double(i) / Double(n), x = noise.next()
            out[i] = (low.process(x) + 0.7 * mid.process(x)) * pow(sin(Double.pi * pow(p, 0.6)), 2)
        }
        return finish(out, gain: 0.34)
    }

    // MARK: - The field

    /// A falling sine with a knock on the front: the wall (`deep` false) or the ground (`deep` true).
    static func thump(deep: Bool) -> [Float] {
        let n = count(0.16)
        var noise = Noise(seed: deep ? 0x7D00_0001 : 0x7D00_0002)
        var soft = Biquad.lowpass(deep ? 500 : 1_100)
        var phase = 0.0
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let hz = (deep ? 92 : 150) * (0.55 + 0.45 * exp(-t / 0.03))
            phase += 2 * Double.pi * hz / sampleRate
            out[i] = sin(phase) * exp(-t / 0.05) + soft.process(noise.next()) * exp(-t / 0.008) * 0.6
        }
        return finish(out, gain: deep ? 0.42 : 0.6)
    }

    // MARK: - The band

    /// Off the wall: the sad trombone. *Womp*, then a longer *wommmp* that sags and wobbles. A
    /// sawtooth through a resonant low-pass that opens and shuts, which is all a wah mute is.
    static func wompWomp() -> [Float] {
        func note(_ dur: Double, from f0: Double, to f1: Double, wobble: Double) -> [Double] {
            let n = count(dur)
            var low = 0.0, band = 0.0, phase = 0.0
            var out = [Double](repeating: 0, count: n)
            for i in 0..<n {
                let t = Double(i) / sampleRate, p = t / dur
                let vibrato = 1 + wobble * p * 0.012 * sin(2 * Double.pi * 5.5 * t)
                phase += (f0 + (f1 - f0) * p * p) * vibrato / sampleRate
                let saw = 2 * (phase - phase.rounded(.down)) - 1
                // The mouth: shut, open by a fifth of the way in, shut again.
                let open = p < 0.2 ? p / 0.2 : pow(1 - (p - 0.2) / 0.8, 1.6)
                let f = 2 * sin(Double.pi * (280 + 1_250 * open) / sampleRate)
                low += f * band
                band += f * (saw - low - 0.45 * band)
                out[i] = low * min(1, t / 0.02) * min(1, (dur - t) / 0.06)
            }
            return out
        }
        let rest = [Double](repeating: 0, count: count(0.07))
        return finish(note(0.30, from: 233, to: 226, wobble: 0) + rest + note(0.85, from: 220, to: 190, wobble: 1), gain: 0.42)
    }

    /// A ballpark organ, one hand: drawbar partials, a click on every key and a Leslie's wobble.
    /// `midi` nil is a rest. Notes are slightly detached, the way an organist prompts a crowd.
    static func organ(_ notes: [(midi: Int?, seconds: Double)], gain: Double = 0.5) -> [Float] {
        let drawbars: [(ratio: Double, level: Double)] = [(0.5, 0.45), (1, 1), (1.5, 0.5), (2, 0.7), (3, 0.35), (4, 0.25)]
        var noise = Noise(seed: 0x0464_0001)
        var out: [Double] = []
        for note in notes {
            let n = count(note.seconds)
            guard let midi = note.midi else { out += [Double](repeating: 0, count: n); continue }
            let hz = 440 * pow(2, Double(midi - 69) / 12)
            let held = note.seconds * 0.9
            var phases = [Double](repeating: 0, count: drawbars.count)
            for i in 0..<n {
                let t = Double(i) / sampleRate
                let spin = sin(2 * Double.pi * 6.2 * t)
                var tone = 0.0
                for k in drawbars.indices {
                    phases[k] += hz * drawbars[k].ratio * (1 + 0.0035 * spin) / sampleRate
                    tone += sin(2 * Double.pi * phases[k]) * drawbars[k].level
                }
                let click = noise.next() * exp(-t / 0.004) * 0.5
                let shape = min(1, t / 0.006) * max(0, min(1, (held - t) / 0.02))
                out.append((tone / 3.2 * (1 + 0.12 * spin) + click) * shape)
            }
        }
        return finish(out, gain: gain)
    }

    /// The rally prompt: a run up the scale that speeds toward a held top note, asking the crowd
    /// a question. Deliberately **not** the famous six-note "Charge!" fanfare, which was written
    /// in 1946 and is still somebody's property; a major scale is nobody's.
    static func chargeRun() -> [Float] {
        let run: [(midi: Int?, seconds: Double)] = [
            (72, 0.15), (74, 0.14), (76, 0.13), (77, 0.12), (79, 0.11), (81, 0.10), (83, 0.09), (84, 0.42),
        ]
        return organ(run, gain: 0.55)
    }

    /// How long `chargeRun` lasts: when the crowd answers.
    static let chargeRunSeconds = 1.26

    /// The answer: a few dozen people shouting one open syllable at once, with the hiss of its
    /// first consonant on the front. *CHARGE!*
    static func crowdShout() -> [Float] {
        let dur = 0.62, n = count(dur)
        var out = [Double](repeating: 0, count: n)
        var pick = Noise(seed: 0xC4A6_0001)
        for v in 0..<14 {
            let f0 = 150 + 70 * (pick.next() + 1), late = count(0.02 * (pick.next() + 1))
            let voice = syllable(dur - 0.06, from: f0 * 1.12, to: f0 * 0.82, growl: 0.35, breath: 0.5,
                                 seed: 0xC4A6_1000 &+ UInt32(v),
                                 formants: [Formant(hz: 720, q: 3.5, gain: 1), Formant(hz: 1_180, q: 4, gain: 0.8),
                                            Formant(hz: 2_600, q: 6, gain: 0.35)])
            for i in 0..<voice.count where late + i < n { out[late + i] += voice[i] / 5 }
        }
        var hiss = Biquad.highpass(2_800), air = Noise(seed: 0xC4A6_0002)
        for i in 0..<count(0.09) { out[i] += hiss.process(air.next()) * exp(-Double(i) / sampleRate / 0.03) * 0.5 }
        for i in 0..<n {
            let t = Double(i) / sampleRate
            out[i] *= min(1, t / 0.025) * (t < 0.22 ? 1 : exp(-(t - 0.22) / 0.16))
        }
        return finish(out, gain: 0.7)
    }

    // MARK: - The rest of the organ (#17): three more tunes for `Synth.organ`

    // Claude's transcriptions, unreviewed — nobody has heard these against the real songs yet
    // (DESIGN.md §11). All three are public domain on purpose: "Three Blind Mice" is a trad.
    // English round first printed in 1609, Chopin's "Marche funèbre" (Piano Sonata No. 2) was
    // written in 1837, and "Take Me Out to the Ball Game" (Norworth/Von Tilzer) is from 1908.
    // None of them is the 1946 "Charge!" fanfare or any other stadium prompt still under licence.

    /// Beats → seconds at a tune's own tempo, so each tune reads as a note table plus one knob.
    private static func beats(_ n: Double, bpm: Double) -> Double { n * 60 / bpm }

    /// Turns a `(midi, beats)` table into the `(midi, seconds)` one `organ` wants, at `bpm`.
    private static func timed(_ tune: [(midi: Int?, beats: Double)], bpm: Double) -> [(midi: Int?, seconds: Double)] {
        tune.map { (midi: $0.midi, seconds: beats($0.beats, bpm: bpm)) }
    }

    /// *Three Blind Mice*, the opening call — "Three blind mice, three blind mice", mi-re-do
    /// twice, the third note of each pair held. There is no third strike in this game, so the
    /// cue is two called strikes in a row (`DerbyMachine.calledStrikesInARow`); it fires with no
    /// lead-in, so it must clear the gap (`missHold` + `windup`, ~1.7 s) on its own, which this
    /// clears at ~1.6 s.
    static let threeBlindMiceBPM = 300.0
    static let threeBlindMiceTune: [(midi: Int?, beats: Double)] = [
        (64, 1), (62, 1), (60, 2), (64, 1), (62, 1), (60, 2),
    ]
    static func threeBlindMice() -> [Float] { organ(timed(threeBlindMiceTune, bpm: threeBlindMiceBPM), gain: 0.5) }

    /// Chopin's *Marche funèbre*, the opening bars' motif in B-flat minor: a dotted "dum,
    /// dum-da-dum" on the tonic (the first bar, 6 beats), then a turn down through the
    /// neighbour tones and back — "Db-C, C-Bb, Bb-A-Bb" (the next 8). Fires (with
    /// `mournStreak`'s usual lead-in) when a home-run streak of 5+ dies — `streakOver`'s three
    /// notes down still cover 3–4, unchanged. The real tempo is a slow Lento; this is only fast
    /// enough that the first bar clears the tightest gap before the next windup, at ~1.6 s — the
    /// turn is **not** guaranteed to fit. `.pitchThrown` cuts the organ off dead if the pitch
    /// gets there first, same as the charge prompt: that's the organ's normal behaviour (§11),
    /// not a bug, so this is deliberately *not* compressed to always finish.
    static let funeralMarchBPM = 225.0
    static let funeralMarchTune: [(midi: Int?, beats: Double)] = [
        (58, 2), (58, 1.5), (58, 0.5), (58, 2),
        (61, 1.5), (60, 0.5), (60, 1.5), (58, 0.5), (58, 1.5), (57, 0.5), (58, 2),
    ]
    static func funeralMarch() -> [Float] { organ(timed(funeralMarchTune, bpm: funeralMarchBPM), gain: 0.5) }

    /// *Take Me Out to the Ball Game*, the chorus's first two lines, in 3/4 — "Take(low) me(up an
    /// octave) out to the ball game, take me out with the crowd." The octave leap on "Take me" is
    /// the tune's signature. Plays over the stats board, which stops the machine clock, so there
    /// is no gap to clear here.
    static let takeMeOutBPM = 150.0
    static let takeMeOutTune: [(midi: Int?, beats: Double)] = [
        (60, 2), (72, 1), (69, 1), (67, 1), (64, 1), (67, 3), (62, 3),
        (60, 2), (72, 1), (69, 1), (67, 1), (64, 1), (67, 6),
    ]
    static func takeMeOut() -> [Float] { organ(timed(takeMeOutTune, bpm: takeMeOutBPM), gain: 0.45) }

    /// How long `takeMeOut` lasts: when the stats board's organ may loop it once more. Computed
    /// from the table itself, not a literal, so it can never drift from it again.
    static let takeMeOutSeconds = takeMeOutTune.reduce(0) { $0 + beats($1.beats, bpm: takeMeOutBPM) }

    /// A record just fell (#41): a rising major arpeggio that overshoots its top note by a
    /// semitone and settles back onto it, held. **Original** — a triad and a turn are not a
    /// melody anybody owns, and nothing in this game's organ may need a licence (§11). In the
    /// style of `chargeRun`, and about as long: it has to fit inside the 1.30 s result hold,
    /// and `.pitchThrown` cuts it off dead if the next pitch gets there first, as it does every
    /// organ cue. Claude's, unreviewed — nobody has heard it yet.
    static let newRecordTune: [(midi: Int?, seconds: Double)] = [
        (72, 0.10), (76, 0.09), (79, 0.09), (84, 0.13), (83, 0.08), (84, 0.44),
    ]
    static func newRecordFlourish() -> [Float] { organ(newRecordTune, gain: 0.55) }
    /// Computed from the table, never a literal.
    static let newRecordSeconds = newRecordTune.reduce(0) { $0 + $1.seconds }

    // MARK: - Beeps and boops

    /// Square-wave notes played one after another.
    static func boops(_ notes: [(hz: Double, seconds: Double)], gain: Double = 0.22) -> [Float] {
        var out: [Double] = []
        for note in notes {
            var phase = 0.0
            for i in 0..<count(note.seconds) {
                phase += note.hz / sampleRate
                let square = (phase - phase.rounded(.down)) < 0.5 ? 1.0 : -1.0
                let t = Double(i) / sampleRate
                out.append(square * min(1, t / 0.004) * min(1, (note.seconds - t) / 0.012))
            }
        }
        return finish(out, gain: gain)
    }

    /// A streak of three or more just ended: three steps down.
    static func streakOver() -> [Float] { boops([(392, 0.09), (294, 0.09), (220, 0.18)]) }

    /// Called up to The Show: a major arpeggio, up.
    static func calledUp() -> [Float] { boops([(523, 0.09), (659, 0.09), (784, 0.09), (1_047, 0.28)], gain: 0.26) }

    /// A record fell in a park with no organist (#41): `newRecordTune`'s own figure in square
    /// waves — the same six notes, so the cue is one idea in two voices rather than two cues.
    static func newRecordBeeps() -> [Float] {
        boops([(523, 0.09), (659, 0.08), (784, 0.08), (1_047, 0.12), (988, 0.07), (1_047, 0.30)],
              gain: 0.26)
    }

    // MARK: - Fireworks (issue #14, "life": fireworks, sky and backdrops)

    /// One shell's burst: a short noise pop on the front, then a scatter of sparks crackling off
    /// as it fades. Mixed under the cheer, one per shell (DESIGN.md §17 "Sound").
    static func fireworkPop() -> [Float] {
        let dur = 0.5, n = count(dur)
        var body = Biquad.bandpass(1_400, q: 0.9)
        var noise = Noise(seed: 0xF12E_0001)
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            out[i] = body.process(noise.next()) * exp(-t / 0.03)
        }
        var hiss = Biquad.highpass(3_200)
        var pick = Noise(seed: 0xF12E_0002)
        for spark in 0..<10 {
            let start = count(0.05 + 0.35 * (0.5 + 0.5 * pick.next()))
            for j in 0..<count(0.02) where start + j < n {
                let t = Double(j) / sampleRate
                out[start + j] += hiss.process(pick.next()) * exp(-t / 0.006) * (0.30 + 0.05 * Double(spark % 3))
            }
        }
        return finish(out, gain: 0.4)
    }
}
