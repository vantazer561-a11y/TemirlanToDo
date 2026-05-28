import SwiftUI

@main
struct TemirlanToDoApp: App {
    @StateObject private var store = TaskStore()
    @StateObject private var settingsStore = NotificationSettingsStore()
    @StateObject private var scheduler = NotificationScheduler()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(store)
                    .environmentObject(settingsStore)
                    .environmentObject(scheduler)

                if showingSplash {
                    LaunchSplashView(isVisible: $showingSplash)
                        .transition(.opacity)
                }
            }
            .onAppear {
                // Проводим closure от TaskStore к NotificationScheduler:
                // любое сохранение задач триггерит пересинхронизацию pending-запросов.
                // _Requirements: 6.8, 7.6, 7.9, 7.11_
                let scheduler = scheduler
                let settingsStore = settingsStore
                store.notifySchedulerNeedsSync = { [weak store] in
                    guard let store else { return }
                    Task { @MainActor in
                        await scheduler.synchronize(
                            with: store.tasks,
                            settings: settingsStore.settings
                        )
                    }
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    // При возврате в активное состояние — обновляем статус и
                    // перепланируем уведомления. _Requirements: 5.7, 5.8, 7.11_
                    Task { @MainActor in
                        await scheduler.refreshAuthorizationStatus()
                        await scheduler.synchronize(
                            with: store.tasks,
                            settings: settingsStore.settings
                        )
                    }
                }
            }
        }
    }
}
