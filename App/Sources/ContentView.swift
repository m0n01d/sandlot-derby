import SwiftUI

/// Full-screen host for the game. No chrome, no menus — just the canvas.
struct ContentView: View {
    @State private var controller = GameController()

    var body: some View {
        GameView(controller: controller)
            .ignoresSafeArea()
            .background(Color.black)
            .statusBar(hidden: true)
    }
}
