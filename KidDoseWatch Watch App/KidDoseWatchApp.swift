import SwiftUI

@main
struct KidDoseWatchApp: App {

    @State private var sessionManager = WatchSessionManager.shared

    init() {
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sessionManager)
        }
    }
}
