import Foundation

/// SplitMix64. Small, fast, and the same on every platform, which is what a shareable park
/// number needs. (g0lf used mulberry32 for the same reason.)
public struct SplitMix64: RandomNumberGenerator, Equatable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Everything that varies between parks. Three numbers and a flag.
public struct Park: Equatable {
    public let number: Int
    public let wallDistanceFeet: Double
    public let wallHeightFeet: Double
    public let isNight: Bool

    public init(number: Int, wallDistanceFeet: Double, wallHeightFeet: Double, isNight: Bool) {
        self.number = number; self.wallDistanceFeet = wallDistanceFeet
        self.wallHeightFeet = wallHeightFeet; self.isNight = isNight
    }

    /// Park 1 is always the same friendly park.
    public static let first = Park(number: 1, wallDistanceFeet: 380, wallHeightFeet: 10, isNight: false)

    public struct Rules: Equatable {
        public var wallDistance: ClosedRange<Double> = 330...410
        public var wallHeight: ClosedRange<Double> = 6...26
        public var nightProbability = 0.25
        public init() {}
        public static let standard = Rules()
    }

    /// Park N is a pure function of N. Anyone on park 1,000 sees the same wall.
    public static func generate(number: Int, rules: Rules = .standard) -> Park {
        if number <= 1 { return .first }
        var g = SplitMix64(seed: UInt64(number) &* 0x2545_F491_4F6C_DD1D)
        let dist = Double(Int(Double.random(in: rules.wallDistance, using: &g)))
        let height = Double(Int(Double.random(in: rules.wallHeight, using: &g)))
        let night = Double.random(in: 0..<1, using: &g) < rules.nightProbability
        return Park(number: number, wallDistanceFeet: dist, wallHeightFeet: height, isNight: night)
    }
}
