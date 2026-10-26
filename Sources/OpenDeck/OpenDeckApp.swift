import SwiftUI

@main
struct OpenDeckApp: App {
    @State private var session = DJSession()

    var body: some Scene {
        WindowGroup("OpenDeck") {
            ContentView(session: session)
                .frame(minWidth: 1_080, minHeight: 680)
        }
        .windowResizability(.contentMinSize)
    }
}
