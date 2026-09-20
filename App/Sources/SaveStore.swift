import Foundation
import DerbyCore

/// Everything that survives a relaunch: which park you are in and every career number.
/// The pitch sequence is not saved; a relaunch reseeds it. Neither is the advance the machine
/// owes at the ceiling (DESIGN.md §16) — that is one more Triple-A home run, with the fanfare.
///
/// Both §16 fields are optional so that a blob written before the paywall still decodes: a
/// missing key reads as nil and `GameController` decides what nil means, which for
/// `grandfathered` is the whole of the grandfathering rule.
struct SaveState: Codable {
    var parkNumber: Int
    var tally: Tally
    /// The contract card is offered automatically exactly once per career. nil is "not yet".
    var contractOffered: Bool?
    /// Entitled for good because this save was already in The Show on the first launch of the
    /// paywalled build. nil means the question has not been asked of this save yet.
    var grandfathered: Bool?
}

/// `UserDefaults`, one JSON blob (DESIGN.md §2). `Tally` is a keyed bag, so a save from an
/// older or newer build still loads.
enum SaveStore {
    private static let key = "save.v1"

    /// A `-autoslice` run is a robot's career, not the player's: it neither reads nor writes.
    /// `-nosave` does the same for a human: a fresh Single-A every launch. `-contract` is a
    /// `-nosave` that starts in Triple-A, and `-park n` drops you into one park for a screenshot,
    /// and `-streak n` fakes a streak that never happened; none of them may overwrite a real career. `Store` gates its entitlement cache on this too, so a
    /// dev run cannot leave a purchase behind in a real one.
    static let isEnabled = !ProcessInfo.processInfo.arguments.contains {
        $0 == "-autoslice" || $0 == "-nosave" || $0 == "-contract" || $0 == "-declined" || $0 == "-park" || $0 == "-streak"
    }

    static func load() -> SaveState? {
        guard isEnabled, let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SaveState.self, from: data)
    }

    static func save(_ state: SaveState) {
        guard isEnabled, let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
