import SwiftUI

@main
struct TemirlanToDoApp: App {
    @StateObject private var store = TaskStore()
    @State private var showingSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(store)

                if showingSplash {
                    LaunchSplashView(isVisible: $showingSplash)
                        .transition(.opacity)
                }
            }
        }
    }
}
