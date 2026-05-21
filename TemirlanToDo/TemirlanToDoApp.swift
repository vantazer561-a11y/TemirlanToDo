import SwiftUI

@main
struct TemirlanToDoApp: App {
    @StateObject private var store = TaskStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
