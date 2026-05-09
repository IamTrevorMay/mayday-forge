import SwiftUI

@main
struct MaydayForgeApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    appState.engine.startAll()
                }
        }
        .defaultSize(width: 1100, height: 700)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
