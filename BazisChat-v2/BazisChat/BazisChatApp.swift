import SwiftUI

@main
struct BazisChatApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appLock = AppLock()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appLock)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                appLock.lock()
            case .active:
                appLock.unlock()
            default:
                break
            }
        }
    }
}
