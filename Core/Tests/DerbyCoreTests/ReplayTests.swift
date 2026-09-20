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
        var isNight: Bool

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
        var fireworksIsNight: Bool?

        var secondsPlayed: Double
        var homeRunStreak: Int
        var pitches: Int
        var homeRuns: Int
        var totalFeet: Int
        var longestFeet: Int

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
            isNight = m.park.isNight

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
            fireworksIsNight = m.fireworks?.isNight

            secondsPlayed = m.tally[.secondsPlayed]
            homeRunStreak = m.tally.homeRunStreak
            pitches = m.tally.pitches
            homeRuns = m.tally.homeRuns
            totalFeet = m.tally.totalFeet
            longestFeet = m.tally.longestFeet
        }
    }

    private let dt = 1.0 / 60

    /// Walks a fresh machine to `.pitch` and hands back the crossing a perfect swing would make.
    private func machineAtThePitch(seed: UInt64 = 99, park: Park = .first,
                                   tally: Tally = Tally()) -> DerbyMachine {
        var m = DerbyMachine(seed: seed, park: park, tally: tally)
        while m.beat != .pitch { m.tick(dt) }
        // Most of the way to the plate, where a real finger meets it.
        while m.pitchProgress < 0.9 { m.tick(dt) }
        return m
    }

    private func perfectCrossing(_ m: DerbyMachine) -> SliceCrossing {
        SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 28, power: 1,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
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
