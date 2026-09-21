import XCTest
@testable import DerbyCore

/// The replay clip (#4) is only worth anything if a rebuilt machine is the same machine. These
/// tests walk the original and the rebuild side by side at a fixed 1/60 and compare every number
/// a frame draws, on every frame, from the contact freeze to the end of the landing number.
final class ReplayTests: XCTestCase {

    /// Everything `AtBatScene.render` and `WideScene.render` read out of the machine. If two
    /// machines agree on this for every frame, they draw the same clip.
    private struct Observed: Equatable {
        var beat: Beat
        var elapsed: Double
        var playbackIndex: Double
        var flightCamera: FlightCamera
        var isBarrelNow: Bool
        var contactHoldNow: Double
        var lastCall: Call?
        var coachingWord: String?
        var isBeingCalledUp: Bool

        var parkNumber: Int
        var wallDistanceFeet: Double
        var wallHeightFeet: Double
        var nightSeed: Bool
        /// The phase the frame is drawn in (§20). It is a machine input, so a clip that
        /// reproduced every other field but this one would still draw a different sky.
        var phase: DayPhase

        var exitVelocityMPH: Double?
        var launchAngleDegrees: Double?
        var distanceFeet: Double?
        var apexFeet: Double?
        var homeRun: Bool?
        var wallHit: Bool?
        var pointCount: Int?

        var ballXFeet: Double?
        var ballYFeet: Double?
        var ballTime: Double?

        var fireworksShells: Int?
        var fireworksSeed: UInt64?
        var fireworksStart: Double?
        var fireworksLampsOn: Bool?

        var secondsPlayed: Double
        var homeRunStreak: Int
        var pitches: Int
        var homeRuns: Int
        var totalFeet: Int
        var longestFeet: Int

        /// Whichever streak is live (§18): the career's, or the Warm Up's while one is running.
        var streakNow: Int
        /// `warmUp`'s visible fields (#33) — nil outside a Warm Up on both sides alike.
        var warmUpDay: Int?
        var warmUpSpent: Int?
        var warmUpTotal: Int?
        var warmUpHomeRunStreak: Int?

        init(_ m: DerbyMachine) {
            beat = m.beat
            elapsed = m.elapsed
            playbackIndex = m.playbackIndex
            flightCamera = m.flightCamera
            isBarrelNow = m.isBarrelNow
            contactHoldNow = m.contactHoldNow
            lastCall = m.lastCall
            coachingWord = m.coachingWord
            isBeingCalledUp = m.isBeingCalledUp

            parkNumber = m.park.number
            wallDistanceFeet = m.park.wallDistanceFeet
            wallHeightFeet = m.park.wallHeightFeet
            nightSeed = m.park.nightSeed
            phase = m.phase

            exitVelocityMPH = m.launch?.exitVelocityMPH
            launchAngleDegrees = m.launch?.launchAngleDegrees
            distanceFeet = m.flight?.distanceFeet
            apexFeet = m.flight?.apexFeet
            homeRun = m.flight?.homeRun
            wallHit = m.flight?.wallHit
            pointCount = m.flight?.points.count

            ballXFeet = m.playbackPoint?.xFeet
            ballYFeet = m.playbackPoint?.yFeet
            ballTime = m.playbackPoint?.time

            fireworksShells = m.fireworks?.shellCount
            fireworksSeed = m.fireworks?.seed
            fireworksStart = m.fireworks?.start
            fireworksLampsOn = m.fireworks?.lampsOn

            secondsPlayed = m.tally[.secondsPlayed]
            homeRunStreak = m.tally.homeRunStreak
            pitches = m.tally.pitches
            homeRuns = m.tally.homeRuns
            totalFeet = m.tally.totalFeet
            longestFeet = m.tally.longestFeet

            streakNow = m.streakNow
            warmUpDay = m.warmUp?.card.day
            warmUpSpent = m.warmUp?.spent
            warmUpTotal = m.warmUp?.total
            warmUpHomeRunStreak = m.warmUp?.homeRunStreak
        }
    }

    private let dt = 1.0 / 60

    /// Walks a fresh machine to `.pitch` and hands back the crossing a perfect swing would make.
    private func machineAtThePitch(seed: UInt64 = 99, park: Park = .first,
                                   tally: Tally = Tally(),
                                   phase: DayPhase = .midday) -> DerbyMachine {
        var m = DerbyMachine(seed: seed, park: park, tally: tally, phase: phase)
        while m.beat != .pitch { m.tick(dt) }
        // Most of the way to the plate, where a real finger meets it.
        while m.pitchProgress < 0.9 { m.tick(dt) }
        return m
    }

    private func perfectCrossing(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 28, power: 1,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    /// The same as `machineAtThePitch`, but mid a Warm Up (#33): a career that has cleared a park
    /// queues the day's ten, the queue takes the field at the next windup, and the walk continues
    /// from there. `resuming` defaults to none, so the captured pitch is the day's first — never
    /// the tenth — which is what proves a clip does not spend the pitch it merely shows again.
    private func warmUpMachineAtThePitch(day: Int = 20260919, seed: UInt64 = 99,
                                         resuming: [WarmUpPitch] = []) -> DerbyMachine {
        var tally = Tally()
        tally.set(.parksCleared, 1)
        var m = DerbyMachine(seed: seed, park: .first, tally: tally)
        m.beginWarmUp(WarmUp.generate(day: day), resuming: resuming)
        while m.warmUp == nil { m.tick(dt) }              // takes the field at the next windup
        while m.beat != .pitch { m.tick(dt) }
        while m.pitchProgress < 0.9 { m.tick(dt) }
        return m
    }

    private let marksSlash = Point(x: 0.891, y: -0.454)
    private let marksTrail = [Point(x: 120, y: 160), Point(x: 140, y: 148), Point(x: 166, y: 138)]

    private func record(_ m: DerbyMachine, _ c: SliceCrossing) -> Replay {
        Replay(capturing: m, crossing: c, slash: marksSlash, trail: marksTrail)
    }

    // MARK: - The one that matters

    /// Play a home run, capture the record at contact, rebuild, and tick both at 1/60 through the
    /// end of `.result` comparing every observable number on every frame.
    func testRebuiltMachineMatchesFrameForFrameThroughResult() {
        var live = machineAtThePitch()
        let crossing = perfectCrossing(live)
        let replay = record(live, crossing)
        live.slice(crossing)

        var rebuilt = Replay.machine(from: replay)

        XCTAssertEqual(live.flight?.homeRun, true, "the fixture swing must be a home run")
        XCTAssertEqual(Observed(rebuilt), Observed(live), "the two differ before the first tick")

        var frames = 0
        while true {
            let liveOut = live.tick(dt)
            let rebuiltOut = rebuilt.tick(dt)
            frames += 1
            XCTAssertEqual(rebuiltOut, liveOut, "transitions differ on frame \(frames)")
            XCTAssertEqual(Observed(rebuilt), Observed(live), "state differs on frame \(frames)")
            if liveOut.contains(.cutToAtBat) { break }        // the result hold is over
            XCTAssertLessThan(frames, 2_000, "the clip never ended")
        }
        // Contact freeze + flight playback + a 1.3 s hold is never a handful of frames.
        XCTAssertGreaterThan(frames, 100)
    }

    /// The same, with a streak already going, so the fireworks show is in the clip too
    /// (DESIGN.md §17: the replay "reproduces the sky, the birds and the fireworks exactly").
    func testFireworksShowIsReproducedExactly() {
        var tally = Tally()
        tally.set(.homeRunStreak, 4)
        tally.set(.bestHomeRunStreak, 4)
        var live = machineAtThePitch(seed: 7, park: Park.generate(number: 12), tally: tally)
        let crossing = perfectCrossing(live)
        let replay = record(live, crossing)
        live.slice(crossing)
        var rebuilt = Replay.machine(from: replay)

        var sawFireworks = false
        while true {
            let out = live.tick(dt)
            rebuilt.tick(dt)
            if let show = live.fireworks {
                sawFireworks = true
                XCTAssertEqual(rebuilt.fireworks, show)
                // The drawn particles, not just the seed: this is what the frame actually reads.
                let a = Fireworks.particles(show: show, at: live.tally[.secondsPlayed],
                                            rules: live.fireworksRules)
                let b = Fireworks.particles(show: rebuilt.fireworks!, at: rebuilt.tally[.secondsPlayed],
                                            rules: rebuilt.fireworksRules)
                XCTAssertEqual(a.count, b.count)
                for (p, q) in zip(a, b) {
                    XCTAssertEqual(p.x, q.x)
                    XCTAssertEqual(p.y, q.y)
                    XCTAssertEqual(p.visible, q.visible)
                    XCTAssertEqual(p.size, q.size)
                }
            }
            if out.contains(.cutToAtBat) { break }
        }
        XCTAssertTrue(sawFireworks, "a streak of 5 must earn a show")
    }

    // MARK: - A Warm Up home run (#33)

    /// The bug this fixes: a clip made during a Warm Up used to rebuild as a career swing, because
    /// `Replay` carried no idea a Warm Up was running. Same walk as
    /// `testRebuiltMachineMatchesFrameForFrameThroughResult`, but mid the day's ten — the rebuild
    /// must agree with the original on `warmUp`'s own fields too, and, since a clip is a recording
    /// and not a pitch, must never end the Warm Up it is only showing again.
    func testRebuiltMachineMatchesFrameForFrameThroughResultDuringWarmUp() {
        var live = warmUpMachineAtThePitch()
        XCTAssertNotNil(live.warmUp, "fixture must actually be mid Warm Up")
        let crossing = perfectCrossing(live)
        let replay = record(live, crossing)
        live.slice(crossing)

        var rebuilt = Replay.machine(from: replay)

        XCTAssertEqual(live.flight?.homeRun, true, "the fixture swing must be a home run")
        XCTAssertNotNil(rebuilt.warmUp, "the rebuild must know it is in a Warm Up (#33)")
        XCTAssertEqual(Observed(rebuilt), Observed(live), "the two differ before the first tick")

        var frames = 0
        var sawWarmUpEnded = false
        while true {
            let liveOut = live.tick(dt)
            let rebuiltOut = rebuilt.tick(dt)
            frames += 1
            XCTAssertEqual(rebuiltOut, liveOut, "transitions differ on frame \(frames)")
            XCTAssertEqual(Observed(rebuilt), Observed(live), "state differs on frame \(frames)")
            if rebuiltOut.contains(where: { if case .warmUpEnded = $0 { return true } else { return false } }) {
                sawWarmUpEnded = true
            }
            if liveOut.contains(.cutToAtBat) { break }        // the result hold is over
            XCTAssertLessThan(frames, 2_000, "the clip never ended")
        }
        XCTAssertNotNil(rebuilt.warmUp, "a clip is a recording, not a pitch: it must not end the Warm Up (#33)")
        XCTAssertFalse(sawWarmUpEnded, "a Warm Up clip must never emit .warmUpEnded (#33)")
        XCTAssertGreaterThan(frames, 100)
    }

    /// The record survives `Codable`, including the Warm Up it carries.
    func testWarmUpRecordRoundTripsThroughJSON() throws {
        var live = warmUpMachineAtThePitch(day: 20260919, seed: 4242)
        let crossing = perfectCrossing(live)
        let replay = record(live, crossing)
        live.slice(crossing)
        XCTAssertNotNil(replay.warmUp)

        let data = try JSONEncoder().encode(replay)
        let decoded = try JSONDecoder().decode(Replay.self, from: data)
        XCTAssertEqual(decoded, replay)
        XCTAssertNotNil(decoded.warmUp)

        var fromJSON = Replay.machine(from: decoded)
        var direct = Replay.machine(from: replay)
        while true {
            let out = direct.tick(dt)
            fromJSON.tick(dt)
            XCTAssertEqual(Observed(fromJSON), Observed(direct))
            if out.contains(.cutToAtBat) { break }
        }
    }

    /// A record written before #33 has no `warmUp` key at all — not even a null one, since a
    /// career swing already encodes an absent optional by omitting the key. It must still decode,
    /// into a replay that has never heard of a Warm Up.
    func testRecordWithoutWarmUpKeyStillDecodes() throws {
        var live = machineAtThePitch()
        let crossing = perfectCrossing(live)
        let replay = record(live, crossing)
        live.slice(crossing)

        let data = try JSONEncoder().encode(replay)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("the record did not encode as a JSON object")
        }
        XCTAssertNil(object["warmUp"], "a career swing already encodes with no warmUp key")
        object.removeValue(forKey: "warmUp")   // belt and braces, in case that ever changes
        let json = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Replay.self, from: json)
        XCTAssertNil(decoded.warmUp)
        XCTAssertNil(Replay.machine(from: decoded).warmUp)
    }

    // MARK: - The record itself

    /// `machine(from:)` hands back a machine standing at the very start of the contact beat.
    func testRebuiltMachineStartsAtTheContactBeat() {
        var live = machineAtThePitch()
        let crossing = perfectCrossing(live)
        let rebuilt = Replay.machine(from: record(live, crossing))
        XCTAssertEqual(rebuilt.beat, .contact)
        XCTAssertEqual(rebuilt.elapsed, 0)
        XCTAssertEqual(rebuilt.playbackIndex, 0)
        XCTAssertNotNil(rebuilt.launch)
        XCTAssertNotNil(rebuilt.flight)
    }

    /// The swing is counted exactly once by the rebuild, not twice and not never.
    func testTheSwingIsCountedOnceByTheRebuild() {
        var live = machineAtThePitch()
        let before = live.tally.pitches
        let crossing = perfectCrossing(live)
        let replay = record(live, crossing)
        live.slice(crossing)
        let rebuilt = Replay.machine(from: replay)
        XCTAssertEqual(replay.tally.pitches, before, "the record is taken before the swing")
        XCTAssertEqual(rebuilt.tally.pitches, before + 1)
        XCTAssertEqual(rebuilt.tally.pitches, live.tally.pitches)
        XCTAssertEqual(rebuilt.tally.homeRuns, live.tally.homeRuns)
        XCTAssertEqual(rebuilt.tally.homeRunStreak, live.tally.homeRunStreak)
    }

    /// The whole point of `Codable`: a clip can travel as data and still draw the same.
    func testRecordRoundTripsThroughJSON() throws {
        var live = machineAtThePitch(seed: 4242, park: Park.generate(number: 31))
        let crossing = perfectCrossing(live)
        let replay = record(live, crossing)
        live.slice(crossing)

        let data = try JSONEncoder().encode(replay)
        let decoded = try JSONDecoder().decode(Replay.self, from: data)
        XCTAssertEqual(decoded, replay)

        var fromJSON = Replay.machine(from: decoded)
        var direct = Replay.machine(from: replay)
        while true {
            let out = direct.tick(dt)
            fromJSON.tick(dt)
            XCTAssertEqual(Observed(fromJSON), Observed(direct))
            if out.contains(.cutToAtBat) { break }
        }
        XCTAssertEqual(decoded.marks.slash.point, marksSlash)
        XCTAssertEqual(decoded.marks.trail.map(\.point), marksTrail)
    }

    // MARK: - The phase (§20)

    /// The phase travels by name and a rebuilt machine stands in it before `slice(_:)` runs, so a
    /// clip lights its fireworks against the same sky and finds the same lights-out shot.
    func testThePhaseTravelsByNameAndIsSetBeforeTheSwingIsReplayed() {
        for phase in DayPhase.allCases {
            var live = machineAtThePitch(seed: 5, park: Park.generate(number: 63), phase: phase)
            let crossing = perfectCrossing(live)
            let replay = record(live, crossing)
            live.slice(crossing)
            XCTAssertEqual(replay.phaseName, phase.rawValue)
            XCTAssertEqual(replay.phase, phase)
            XCTAssertEqual(replay.version, 2)
            let rebuilt = Replay.machine(from: replay)
            XCTAssertEqual(rebuilt.phase, phase)
            XCTAssertEqual(rebuilt.fireworks?.lampsOn, live.fireworks?.lampsOn)
            XCTAssertEqual(rebuilt.parkEvents, live.parkEvents, "\(phase.rawValue)")
            XCTAssertEqual(Replay.leadInMachine(from: replay).phase, phase)
        }
    }

    /// A version-1 record has no phase at all. The one thing it said about the sky was the park's
    /// own night flag, which is what chose the sky back then — so it replays as `night`, and
    /// anything else as `midday` (§20 "The replay record").
    func testAVersionOneRecordFallsBackToItsParkNightFlag() throws {
        var live = machineAtThePitch(seed: 5, park: Park.generate(number: 63))
        let crossing = perfectCrossing(live)
        live.slice(crossing)

        for (nightSeed, expected) in [(true, DayPhase.night), (false, DayPhase.midday)] {
            let data = try JSONEncoder().encode(record(machineAtThePitch(), perfectCrossing(machineAtThePitch())))
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var park = object["park"] as? [String: Any] else {
                return XCTFail("the record did not encode as a JSON object")
            }
            // Wind it back to what version 1 wrote: no phase, and the park's flag under its old
            // name — which is still the key `ParkRecord` decodes.
            object.removeValue(forKey: "phaseName")
            object["version"] = 1
            park["isNight"] = nightSeed
            object["park"] = park

            let decoded = try JSONDecoder().decode(
                Replay.self, from: try JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(decoded.phaseName)
            XCTAssertEqual(decoded.park.nightSeed, nightSeed)
            XCTAssertEqual(decoded.phase, expected)
            XCTAssertEqual(Replay.machine(from: decoded).phase, expected)
        }
    }

    /// A name this build has never heard of is a shrug, not a failure — the same leniency
    /// `PitchRecord` gives an unknown pitch type. A clip is a brag, not a save.
    func testAPhaseNameTheGameDoesNotKnowDrawsMidday() throws {
        var live = machineAtThePitch(seed: 5, park: Park.generate(number: 63), phase: .night)
        let crossing = perfectCrossing(live)
        let replay = record(live, crossing)
        live.slice(crossing)

        let data = try JSONEncoder().encode(replay)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("the record did not encode as a JSON object")
        }
        object["phaseName"] = "blueHour"
        let decoded = try JSONDecoder().decode(
            Replay.self, from: try JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.phase, .midday, "an unknown name draws midday, whatever the park is")
    }

    /// The park travels as its own numbers, so a clip does not move when the ladder does.
    func testParkTravelsByValueNotByNumber() {
        var live = machineAtThePitch(seed: 5, park: Park.generate(number: 77))
        let crossing = perfectCrossing(live)
        let replay = record(live, crossing)
        XCTAssertEqual(replay.park.park, live.park)
        XCTAssertEqual(Replay.machine(from: replay).park, live.park)
    }

    /// The pitch survives the trip by name, and the launch it produces is the same one.
    func testPitchRoundTripsByName() {
        for seed in UInt64(1)...12 {
            var live = machineAtThePitch(seed: seed)
            let crossing = perfectCrossing(live)
            let replay = record(live, crossing)
            XCTAssertEqual(replay.pitch.pitch.type.name, live.pitch.type.name)
            XCTAssertEqual(replay.pitch.pitch.speedMPH, live.pitch.speedMPH)
            XCTAssertEqual(replay.pitch.pitch.isStrike, live.pitch.isStrike)
            XCTAssertEqual(replay.pitch.pitch.duration, live.pitch.duration)
            live.slice(crossing)
            let rebuilt = Replay.machine(from: replay)
            XCTAssertEqual(rebuilt.launch?.exitVelocityMPH, live.launch?.exitVelocityMPH)
            XCTAssertEqual(rebuilt.launch?.launchAngleDegrees, live.launch?.launchAngleDegrees)
            XCTAssertEqual(rebuilt.flight?.distanceFeet, live.flight?.distanceFeet)
        }
    }

    /// `isHomeRun` is what the trigger gates on, so it has to agree with the machine.
    func testIsHomeRunAgreesWithTheFlight() {
        var live = machineAtThePitch()
        let good = perfectCrossing(live)
        XCTAssertTrue(record(live, good).isHomeRun)

        // A weak tap: nowhere near the wall, so no clip is offered.
        let weak = SliceCrossing(quality: 0.05, progress: 1, swingAngleDegrees: 4, power: 0.3,
                                 ball: live.ballNow, crossingPoint: live.ballNow.position)
        let weakRecord = record(live, weak)
        XCTAssertFalse(weakRecord.isHomeRun)
        live.slice(weak)
        XCTAssertEqual(weakRecord.isHomeRun, live.flight?.homeRun)
    }
}
