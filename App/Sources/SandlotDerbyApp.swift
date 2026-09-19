import SwiftUI

/// Entry point. Everything else — the machine, the two cameras, the scenes — lives behind
/// `ContentView`; this file only wires the SwiftUI app lifecycle to it.
@main
struct SandlotDerbyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
