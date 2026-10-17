import SwiftUI

@main
struct KaiApp: App {
    @StateObject private var store = ChatStore.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                PingScheduler.shared.appBecameActive(store: store)
            case .background:
                PingScheduler.shared.appWentToBackground(store: store)
            default:
                break
            }
        }
    }
}
