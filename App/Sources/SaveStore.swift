import Foundation
import DerbyCore

/// Everything that survives a relaunch: which park you are in and every career number.
/// The pitch sequence is not saved; a relaunch reseeds it.
struct SaveState: Codable {
    var parkNumber: Int
    var tally: Tally
}

/// `UserDefaults`, one JSON blob (DESIGN.md §2). `Tally` is a keyed bag, so a save from an
/// older or newer build still loads.
enum SaveStore {
    private static let key = "save.v1"

    /// A `-autoslice` run is a robot's career, not the player's: it neither reads nor writes.
    /// `-nosave` does the same for a human: a fresh Single-A every launch. `-streak` (DEBUG,
    /// `GameController`) fakes a career that never happened, so it carries the same rule.
    private static let isEnabled = !ProcessInfo.processInfo.arguments.contains { $0 == "-autoslice" || $0 == "-nosave" || $0 == "-streak" }

    static func load() -> SaveState? {
        guard isEnabled, let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SaveState.self, from: data)
    }

    static func save(_ state: SaveState) {
        guard isEnabled, let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
