import XCTest
@testable import DerbyCore

final class ContactTests: XCTestCase {
    private let rules = SliceRules.standard
    private let pitching = PitchingRules.standard

    private var strikePitch: Pitch {
        Pitch(type: .fastball, speedMPH: 95, isStrike: true, target: Point(x: 170, y: 160))
    }

    private func ballAt(_ pitch: Pitch) -> (Double) -> BallSample {
        { p in Pitching.ball(pitch, at: p, rules: self.pitching) }
    }

    func testSegmentDistance() {
        let a = Point(x: 0, y: 0), b = Point(x: 10, y: 0)
        XCTAssertEqual(Contact.distance(from: Point(x: 5, y: 3), toSegment: a, b), 3, accuracy: 1e-9)
        XCTAssertEqual(Contact.distance(from: Point(x: -4, y: 0), toSegment: a, b), 4, accuracy: 1e-9)
        XCTAssertEqual(Contact.distance(from: Point(x: 13, y: 4), toSegment: a, b), 5, accuracy: 1e-9)
    }

    func testSliceThroughTheBallAtThePlate_isContact() {
        let pitch = strikePitch
        let ball = Pitching.ball(pitch, at: 1.0)
        let a = Point(x: ball.x - 20, y: ball.y + 10)
        let b = Point(x: ball.x + 20, y: ball.y - 10)
        let outcome = Contact.test(segment: a, b, dragStart: a, fingerSpeed: 600, pitch: pitch,
                                   progress: 1.0, ballAt: ballAt(pitch))
        guard case .contact(let c) = outcome else { return XCTFail("expected contact, got \(outcome)") }
        XCTAssertGreaterThan(c.quality, 0.9)
        XCTAssertEqual(c.swingAngleDegrees, 26.6, accuracy: 1.0)   // atan(10/20)
        XCTAssertEqual(c.power, 1.0, accuracy: 1e-9)
        XCTAssertEqual(c.progress, 1.0, accuracy: 1e-9)
    }

    func testSliceWideOfTheBall_isMiss() {
        let pitch = strikePitch
        let ball = Pitching.ball(pitch, at: 1.0)
        let a = Point(x: ball.x + 30, y: ball.y + 10)
        let b = Point(x: ball.x + 50, y: ball.y - 10)
        let outcome = Contact.test(segment: a, b, dragStart: a, fingerSpeed: 600, pitch: pitch,
                                   progress: 1.0, ballAt: ballAt(pitch))
        guard case .miss(let d, _, _) = outcome else { return XCTFail("expected miss, got \(outcome)") }
        XCTAssertGreaterThan(d, ball.radius + rules.hitMarginPixels)
    }

    func testSliceThroughTheBallWhileFar_isEarly() {
        let pitch = strikePitch
        let ball = Pitching.ball(pitch, at: 0.4)
        let a = Point(x: ball.x - 10, y: ball.y + 5)
        let b = Point(x: ball.x + 10, y: ball.y - 5)
        let outcome = Contact.test(segment: a, b, dragStart: a, fingerSpeed: 600, pitch: pitch,
                                   progress: 0.4, ballAt: ballAt(pitch))
        guard case .early = outcome else { return XCTFail("expected early, got \(outcome)") }
    }

    func testLagForgiveness_acceptsWhereTheBallJustWas() {
        // Slice through where the ball was 90 ms ago, at progress 1.0 now.
        let pitch = strikePitch
        let back = 0.09 / pitch.duration
        let then = Pitching.ball(pitch, at: 1.0 - back)
        let now = Pitching.ball(pitch, at: 1.0)
        XCTAssertGreaterThan(abs(now.y - then.y) + abs(now.x - then.x), 0)
        let a = Point(x: then.x - 15, y: then.y), b = Point(x: then.x + 15, y: then.y)
        let outcome = Contact.test(segment: a, b, dragStart: a, fingerSpeed: 400, pitch: pitch,
                                   progress: 1.0, ballAt: ballAt(pitch))
        guard case .contact = outcome else { return XCTFail("expected contact via lag window, got \(outcome)") }
    }

    func testSwingAngleComesFromTheWholeStroke() {
        let pitch = strikePitch
        let ball = Pitching.ball(pitch, at: 1.0)
        // Drag started far below-left; last segment is nearly flat. Angle should follow the stroke.
        let start = Point(x: ball.x - 60, y: ball.y + 60)
        let a = Point(x: ball.x - 8, y: ball.y + 1)
        let b = Point(x: ball.x + 8, y: ball.y - 1)
        let outcome = Contact.test(segment: a, b, dragStart: start, fingerSpeed: 300, pitch: pitch,
                                   progress: 1.0, ballAt: ballAt(pitch))
        guard case .contact(let c) = outcome else { return XCTFail() }
        XCTAssertEqual(c.swingAngleDegrees, 42, accuracy: 3)   // atan(61/68)
    }

    func testResolve_perfectFastballFullPower() {
        let c = SliceCrossing(quality: 1, progress: 1, swingAngleDegrees: 28, power: 1,
                              ball: Pitching.ball(strikePitch, at: 1), crossingPoint: Point(x: 0, y: 0))
        let l = Contact.resolve(c, pitch: strikePitch)
        XCTAssertEqual(l.exitVelocityMPH, 55 + 57 + 3, accuracy: 1e-9)
        XCTAssertEqual(l.launchAngleDegrees, 28, accuracy: 1e-9)
    }

    func testResolve_earlyContactAddsLoft_andClamps() {
        let c = SliceCrossing(quality: 0.5, progress: 0.8, swingAngleDegrees: 60, power: 0.5,
                              ball: Pitching.ball(strikePitch, at: 0.8), crossingPoint: Point(x: 0, y: 0))
        let l = Contact.resolve(c, pitch: strikePitch)
        XCTAssertEqual(l.launchAngleDegrees, 68, accuracy: 1e-9)   // 60 + 0.2*40
        let steep = SliceCrossing(quality: 0.5, progress: 0.5, swingAngleDegrees: 80, power: 0.5,
                                  ball: c.ball, crossingPoint: c.crossingPoint)
        XCTAssertEqual(Contact.resolve(steep, pitch: strikePitch).launchAngleDegrees, 70, accuracy: 1e-9)
    }

    func testPowerFloorAndSpeedOrLength() {
        let pitch = strikePitch
        let ball = Pitching.ball(pitch, at: 1.0)
        let a = Point(x: ball.x - 4, y: ball.y), b = Point(x: ball.x + 4, y: ball.y)
        // Tiny, slow slice: power floors at 0.3.
        guard case .contact(let slow) = Contact.test(segment: a, b, dragStart: a, fingerSpeed: 10, pitch: pitch,
                                                     progress: 1.0, ballAt: ballAt(pitch)) else { return XCTFail() }
        XCTAssertEqual(slow.power, rules.minPower, accuracy: 1e-9)
        // Long drag, slow finger: length carries it.
        let far = Point(x: ball.x - 90, y: ball.y)
        guard case .contact(let long) = Contact.test(segment: a, b, dragStart: far, fingerSpeed: 10, pitch: pitch,
                                                     progress: 1.0, ballAt: ballAt(pitch)) else { return XCTFail() }
        XCTAssertGreaterThan(long.power, 0.9)
    }

    func testBallPitchCapsQuality() {
        let ballPitch = Pitch(type: .fastball, speedMPH: 95, isStrike: false, target: Point(x: 120, y: 160))
        let ball = Pitching.ball(ballPitch, at: 1.0)
        let a = Point(x: ball.x - 20, y: ball.y), b = Point(x: ball.x + 20, y: ball.y)
        guard case .contact(let c) = Contact.test(segment: a, b, dragStart: a, fingerSpeed: 600, pitch: ballPitch,
                                                  progress: 1.0, ballAt: { Pitching.ball(ballPitch, at: $0) }) else { return XCTFail() }
        XCTAssertLessThanOrEqual(c.quality, rules.ballPenalty + 1e-9)
    }
}
