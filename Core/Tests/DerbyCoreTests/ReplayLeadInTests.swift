import XCTest
@testable import DerbyCore

/// The lead-in (#42): a replay starts `ReplayRules.leadInSeconds` before the slash, with the last
/// of the pitch arriving and the finger's stroke being drawn. These tests walk the live pitch and
/// the rebuilt lead-in side by side and compare every number those frames draw.
///
/// The claim is not the same one `ReplayTests` makes. From the freeze on, a rebuild is **bit
/// exact**, because `Replay.machine(from:)` replays one `slice(_:)` call on a machine built from
/// the recorded tally — nothing accumulates. A lead-in accumulates: it ticks a pitch forward from
/// a rolled-back clock, and the live game ticked that same pitch at whatever the display gave. So
/// the lead-in's claim is that it draws the same **pixels** — the ball lands on the same whole
/// design pixel, the beat and the pitch and the labels agree — and the clocks agree to far below
/// a frame. The two machines are separate objects, so nothing here can leak into the clip.
final class ReplayLeadInTests: XCTestCase {

    private let dt = 1.0 / 60
    private let rules = ReplayRules.standard

    /// One frame of the pitch, as the at-bat view draws it.
    private struct PitchFrame: Equatable {
        var beat: Beat
        var ballPixelX: Int
        var ballPixelY: Int
        var ballPixelRadius: Int
        var parkNumber: Int
        var pitchName: String
        var pitchSpeedMPH: Double
        var isStrike: Bool
        var streakNow: Int
        var pitches: Int
        var warmUpDay: Int?
        var warmUpSpent: Int?
        /// Not compared for equality — checked to a tolerance, because both sides accumulate it.
        var elapsed: Double
        var skyClock: Double

        init(_ m: DerbyMachine) {
            beat = m.beat
            let b = m.ballNow
            ballPixelX = Int(b.x.rounded())
            ballPixelY = Int(b.y.rounded())
            ballPixelRadius = Int(b.radius.rounded())
            parkNumber = m.park.number
            pitchName = m.pitch.type.name
            pitchSpeedMPH = m.pitch.speedMPH
            isStrike = m.pitch.isStrike
            streakNow = m.streakNow
            pitches = m.tally.pitches
            warmUpDay = m.warmUp?.card.day
            warmUpSpent = m.warmUp?.spent
            elapsed = m.elapsed
            skyClock = m.skyClock
        }

        /// Everything that has to be identical, which is everything a frame turns into pixels.
        static func == (a: PitchFrame, b: PitchFrame) -> Bool {
            a.beat == b.beat && a.ballPixelX == b.ballPixelX && a.ballPixelY == b.ballPixelY
                && a.ballPixelRadius == b.ballPixelRadius && a.parkNumber == b.parkNumber
                && a.pitchName == b.pitchName && a.pitchSpeedMPH == b.pitchSpeedMPH
                && a.isStrike == b.isStrike && a.streakNow == b.streakNow && a.pitches == b.pitches
                && a.warmUpDay == b.warmUpDay && a.warmUpSpent == b.warmUpSpent
        }
    }

    /// Walks a machine to `.pitch` and then frame by frame to where a finger meets the ball,
    /// keeping every frame of the pitch on the way. The last entry is the frame the slash lands on.
    private func walkThePitch(_ m: inout DerbyMachine) -> [PitchFrame] {
        while m.beat != .pitch { m.tick(dt) }
        var frames: [PitchFrame] = []
        while m.pitchProgress < 0.9 {
            m.tick(dt)
            frames.append(PitchFrame(m))
        }
        return frames
    }

    private func careerMachine(seed: UInt64 = 99, park: Park = .first, tally: Tally = Tally()) -> DerbyMachine {
        DerbyMachine(seed: seed, park: park, tally: tally)
    }

    private func warmUpMachine(day: Int = 20260919, seed: UInt64 = 99) -> DerbyMachine {
        var tally = Tally()
        tally.set(.parksCleared, 1)
        var m = DerbyMachine(seed: seed, park: .first, tally: tally)
        m.beginWarmUp(WarmUp.generate(day: day))
        while m.warmUp == nil { m.tick(dt) }
        return m
    }

    private func perfectCrossing(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 28, power: 1,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    /// The trail a finger leaves on its way through, with a time per sample: five points over the
    /// last 0.15 s, the last of them on the ball.
    private let trail = [Point(x: 108, y: 176), Point(x: 122, y: 168), Point(x: 138, y: 158),
                         Point(x: 152, y: 148), Point(x: 166, y: 138)]
    private let trailTimes = [-0.15, -0.11, -0.07, -0.035, 0.0]

    private func record(_ m: DerbyMachine, _ c: SliceCrossing) -> Replay {
        Replay(capturing: m, crossing: c, slash: Point(x: 0.891, y: -0.454),
               trail: trail, trailTimes: trailTimes)
    }

    // MARK: - The one that matters

    /// The lead-in draws the pitch the player saw. Walk the live pitch keeping every frame, take
    /// the record at contact, rebuild the lead-in and tick it the same number of frames: each one
    /// must land on the same pixels as the live frame the same distance from the slash.
    func testLeadInMatchesTheLivePitchFrameForFrame() {
        var live = careerMachine()
        let liveFrames = walkThePitch(&live)
        let crossing = perfectCrossing(live)
        let replay = record(live, crossing)

        let lead = replay.leadInSeconds(rules: rules)
        XCTAssertEqual(lead, rules.leadInSeconds, accuracy: 1e-12,
                       "a pitch is long enough to give the whole lead-in")
        let leadFrames = Int((lead / dt).rounded())
        XCTAssertGreaterThanOrEqual(liveFrames.count, leadFrames, "the fixture pitch is too short")

        var rebuilt = Replay.leadInMachine(from: replay, rules: rules)
        XCTAssertEqual(rebuilt.beat, .pitch)

        for k in 1...leadFrames {
            rebuilt.tick(dt)
            let mine = PitchFrame(rebuilt)
            let theirs = liveFrames[liveFrames.count - leadFrames + k - 1]
            XCTAssertEqual(mine, theirs, "the lead-in differs from the live pitch on frame \(k)")
            XCTAssertEqual(mine.elapsed, theirs.elapsed, accuracy: 1e-9,
                           "the pitch clock drifted on frame \(k)")
            XCTAssertEqual(mine.skyClock, theirs.skyClock, accuracy: 1e-9,
                           "the sky's clock drifted on frame \(k)")
        }
        // …and it has arrived where the slash is, not somewhere near it.
        XCTAssertEqual(rebuilt.elapsed, replay.pitchElapsedAtContact ?? -1, accuracy: 1e-9)
    }

    /// The same, mid a Warm Up (#33's ground): the day's labels, park and streak have to survive
    /// the lead-in too, or a clip opens on `PARK 20260919` and then cuts to `WARM UP`.
    func testLeadInMatchesTheLivePitchDuringAWarmUp() {
        var live = warmUpMachine()
        let liveFrames = walkThePitch(&live)
        XCTAssertNotNil(live.warmUp, "fixture must actually be mid Warm Up")
        let crossing = perfectCrossing(live)
        let replay = record(live, crossing)
        XCTAssertNotNil(replay.warmUp)

        let leadFrames = Int((replay.leadInSeconds(rules: rules) / dt).rounded())
        var rebuilt = Replay.leadInMachine(from: replay, rules: rules)
        XCTAssertNotNil(rebuilt.warmUp, "the lead-in must know it is in a Warm Up")

        for k in 1...leadFrames {
            rebuilt.tick(dt)
            XCTAssertEqual(PitchFrame(rebuilt), liveFrames[liveFrames.count - leadFrames + k - 1],
                           "the Warm Up lead-in differs on frame \(k)")
        }
        XCTAssertNotNil(rebuilt.warmUp, "a lead-in must not end the Warm Up it is showing again")
    }

    /// The hand-over. A replay ticks the lead-in machine and then **throws it away**, drawing the
    /// freeze and everything after it from `Replay.machine(from:)` — so however long the lead-in
    /// ran, the clip is the same one it has always been. This is the guarantee the app's
    /// `ReplayPlayback` relies on.
    func testTheLeadInCannotDriftIntoTheClip() {
        var live = careerMachine()
        _ = walkThePitch(&live)
        let crossing = perfectCrossing(live)
        let replay = record(live, crossing)
        live.slice(crossing)

        var leadIn = Replay.leadInMachine(from: replay, rules: rules)
        let leadFrames = Int((replay.leadInSeconds(rules: rules) / dt).rounded())
        for _ in 1...leadFrames { leadIn.tick(dt) }
        XCTAssertEqual(leadIn.beat, .pitch, "the lead-in never swings: the hand-over does")

        // Built after the lead-in ran, and still the very machine the clip has always used.
        let atContact = Replay.machine(from: replay)
        XCTAssertEqual(atContact.beat, .contact)
        XCTAssertEqual(atContact.elapsed, 0)
        XCTAssertEqual(atContact.tally[.secondsPlayed], live.tally[.secondsPlayed])
        XCTAssertEqual(atContact.flight?.distanceFeet, live.flight?.distanceFeet)
        XCTAssertEqual(atContact.clockAtContact, live.clockAtContact)
        XCTAssertEqual(atContact.parkEvents, live.parkEvents)
    }

    // MARK: - The stroke

    /// The finger's stroke grows through the lead-in and is whole at the slash.
    func testTheStrokeGrowsThroughTheLeadIn() {
        var live = careerMachine()
        _ = walkThePitch(&live)
        let replay = record(live, perfectCrossing(live))

        XCTAssertEqual(replay.stroke(secondsBeforeContact: 0.4), [], "nothing drawn yet 0.4 s out")
        XCTAssertEqual(replay.stroke(secondsBeforeContact: 0.12).count, 1)
        XCTAssertEqual(replay.stroke(secondsBeforeContact: 0.05).count, 3)
        XCTAssertEqual(replay.stroke(secondsBeforeContact: 0).count, trail.count)
        XCTAssertEqual(replay.stroke(secondsBeforeContact: 0), trail)

        // It only ever grows.
        var last = 0
        for step in stride(from: 0.4, through: 0.0, by: -0.01) {
            let n = replay.stroke(secondsBeforeContact: step).count
            XCTAssertGreaterThanOrEqual(n, last)
            last = n
        }
    }

    /// Times that do not line up with the points are refused rather than half-used.
    func testMismatchedTrailTimesAreDropped() {
        var live = careerMachine()
        _ = walkThePitch(&live)
        let replay = Replay(capturing: live, crossing: perfectCrossing(live),
                            slash: Point(x: 1, y: 0), trail: trail, trailTimes: [0, -0.1])
        XCTAssertNil(replay.marks.trailTimes)
        XCTAssertEqual(replay.stroke(secondsBeforeContact: 0), [])
    }

    // MARK: - Records written before the lead-in existed

    /// No `pitchElapsedAtContact` and no `trailTimes` keys at all: the record still decodes, and
    /// a replay of it simply opens on the freeze, the way every clip did before #42.
    func testRecordWithoutTheLeadInKeysStillDecodes() throws {
        var live = careerMachine()
        _ = walkThePitch(&live)
        let replay = record(live, perfectCrossing(live))

        let data = try JSONEncoder().encode(replay)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("the record did not encode as a JSON object")
        }
        object.removeValue(forKey: "pitchElapsedAtContact")
        if var marks = object["marks"] as? [String: Any] {
            marks.removeValue(forKey: "trailTimes")
            object["marks"] = marks
        }
        let decoded = try JSONDecoder().decode(Replay.self, from:
            try JSONSerialization.data(withJSONObject: object))

        XCTAssertNil(decoded.pitchElapsedAtContact)
        XCTAssertNil(decoded.marks.trailTimes)
        XCTAssertEqual(decoded.leadInSeconds(rules: rules), 0)
        XCTAssertEqual(decoded.stroke(secondsBeforeContact: 0.2), [])
        // And the lead-in machine for such a record stands exactly where the freeze does.
        XCTAssertEqual(Replay.leadInMachine(from: decoded, rules: rules).elapsed, 0)
    }

    /// The whole record, new fields included, survives the round trip.
    func testTheNewFieldsRoundTripThroughJSON() throws {
        var live = careerMachine(seed: 4242, park: Park.generate(number: 31))
        _ = walkThePitch(&live)
        let replay = record(live, perfectCrossing(live))

        let decoded = try JSONDecoder().decode(Replay.self, from: JSONEncoder().encode(replay))
        XCTAssertEqual(decoded, replay)
        XCTAssertEqual(decoded.marks.trailTimes, trailTimes)
        XCTAssertEqual(decoded.pitchElapsedAtContact, replay.pitchElapsedAtContact)
    }

    /// A lead-in never begins before the pitch was thrown, however long the rule asks for.
    func testTheLeadInIsClampedToThePitchItHas() {
        var live = careerMachine()
        while live.beat != .pitch { live.tick(dt) }
        live.tick(dt)                                   // one frame in: 1/60 s of pitch exists
        let replay = record(live, perfectCrossing(live))

        var greedy = ReplayRules.standard
        greedy.leadInSeconds = 5
        XCTAssertEqual(replay.leadInSeconds(rules: greedy), replay.pitchElapsedAtContact ?? -1,
                       accuracy: 1e-12)
        XCTAssertEqual(Replay.leadInMachine(from: replay, rules: greedy).elapsed, 0)
    }

    // MARK: - What is offered a replay at all

    /// The knob, and what it lets through (#42): a home run and a ball off the wall, nothing else.
    func testOfferedForDecidesWhatEarnsTheCamera() {
        let standard = ReplayRules.standard
        XCTAssertTrue(standard.offers(homeRun: true, offTheWall: false))
        XCTAssertTrue(standard.offers(homeRun: false, offTheWall: true))
        XCTAssertFalse(standard.offers(homeRun: false, offTheWall: false))

        var homeRunsOnly = ReplayRules.standard
        homeRunsOnly.offeredFor = [.homeRun]
        XCTAssertTrue(homeRunsOnly.offers(homeRun: true, offTheWall: false))
        XCTAssertFalse(homeRunsOnly.offers(homeRun: false, offTheWall: true))

        var nothing = ReplayRules.standard
        nothing.offeredFor = []
        XCTAssertFalse(nothing.offers(homeRun: true, offTheWall: true))
    }

    /// …and it agrees with the flight the machine actually simulates.
    func testIsWorthSeeingAgainAgreesWithTheFlight() {
        var live = careerMachine()
        _ = walkThePitch(&live)
        let good = perfectCrossing(live)
        XCTAssertTrue(record(live, good).isWorthSeeingAgain(rules: rules))

        // A weak tap: nowhere near the wall, so no camera.
        let weak = SliceCrossing(quality: 0.05, progress: 1, swingAngleDegrees: 4, power: 0.3,
                                 ball: live.ballNow, crossingPoint: live.ballNow.position)
        let weakRecord = record(live, weak)
        XCTAssertFalse(weakRecord.isWorthSeeingAgain(rules: rules))
        live.slice(weak)
        XCTAssertEqual(live.flight?.homeRun, false)
        XCTAssertEqual(live.flight?.wallHit, false)
    }
}
