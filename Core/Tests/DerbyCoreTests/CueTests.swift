import XCTest
@testable import DerbyCore

/// The moments the app hangs a sound or a haptic on. Each fires once, when playback gets there.
final class CueTests: XCTestCase {
    private func crossing(_ m: DerbyMachine, quality: Double, power: Double, angle: Double) -> SliceCrossing {
        SliceCrossing(quality: quality, progress: 1, swingAngleDegrees: angle, power: power,
                      ball: m.ballNow, crossingPoint: m.ballNow.position)
    }

    private func toNextPitch(_ m: inout DerbyMachine) {
        var waited = 0.0
        while m.beat != .pitch && waited < 30 { m.tick(1.0 / 60); waited += 1.0 / 60 }
        XCTAssertEqual(m.beat, .pitch)
    }

    /// Everything emitted from now until the next windup, in order.
    private func playOut(_ m: inout DerbyMachine) -> [Transition] {
        var out: [Transition] = []
        var waited = 0.0
        repeat { out += m.tick(1.0 / 60); waited += 1.0 / 60 } while m.beat != .windup && waited < 30
        return out
    }

    private func count(_ t: Transition, in all: [Transition]) -> Int { all.filter { $0 == t }.count }

    func testAHomeRunClearsTheWallThenLandsOnceEach() {
        var m = DerbyMachine(seed: 3, park: Park.generate(number: 4))
        toNextPitch(&m)
        m.slice(crossing(m, quality: 1, power: 1, angle: 28))
        let t = playOut(&m)
        XCTAssertEqual(count(.clearedWall, in: t), 1)
        XCTAssertEqual(count(.landed, in: t), 1)
        XCTAssertEqual(count(.hitWall, in: t), 0)
        XCTAssertLessThan(t.firstIndex(of: .cutToWide)!, t.firstIndex(of: .clearedWall)!)
        XCTAssertLessThan(t.firstIndex(of: .clearedWall)!, t.firstIndex(of: .landed)!)
        XCTAssertLessThan(t.firstIndex(of: .landed)!, t.firstIndex(of: .cutToAtBat)!)
    }

    func testAShortBallOnlyLands() {
        var m = DerbyMachine(seed: 3, park: Park.generate(number: 4))
        toNextPitch(&m)
        m.slice(crossing(m, quality: 0, power: 0.3, angle: 35))
        XCTAssertFalse(m.flight?.wallHit ?? true)
        let t = playOut(&m)
        XCTAssertEqual(count(.landed, in: t), 1)
        XCTAssertEqual(count(.clearedWall, in: t), 0)
        XCTAssertEqual(count(.hitWall, in: t), 0)
    }

    func testABallOffTheWallSaysSoOnce() {
        // Find a swing that meets the wall below the top; which angle does it is the physics' business.
        for angle in stride(from: 6.0, through: 30, by: 1) {
            var m = DerbyMachine(seed: 3, park: Park.generate(number: 4))
            toNextPitch(&m)
            m.slice(crossing(m, quality: 1, power: 0.8, angle: angle))
            guard let f = m.flight, f.wallHit, !f.homeRun else { continue }
            let t = playOut(&m)
            XCTAssertEqual(count(.hitWall, in: t), 1)
            XCTAssertEqual(count(.clearedWall, in: t), 0)
            return
        }
        XCTFail("no angle from 6 to 30 degrees put a ball off the wall")
    }

    func testATakenPitchIsCalledOnce() {
        var m = DerbyMachine(seed: 12, park: Park.generate(number: 4))
        toNextPitch(&m)
        let expected: Call = m.pitch.isStrike ? .strike : .ball
        let t = playOut(&m)
        XCTAssertEqual(count(.called(expected), in: t), 1)
        XCTAssertEqual(t.filter { if case .called = $0 { return true } else { return false } }.count, 1)
    }

    func testASwingIsNeverCalled() {
        var m = DerbyMachine(seed: 12)
        toNextPitch(&m)
        m.sliceMissed()
        let t = playOut(&m)
        XCTAssertTrue(t.allSatisfy { if case .called = $0 { return false } else { return true } })
    }
}
