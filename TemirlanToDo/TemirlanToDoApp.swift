import SwiftUI
import UserNotifications

@main
struct TemirlanToDoApp: App {
    @StateObject private var store = TaskStore()
    @StateObject private var settingsStore = NotificationSettingsStore()
    @StateObject private var scheduler = NotificationScheduler()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSplash = true
    @State private var didRequestAuthorizationOnStart = false

    init() {
        // Регистрируем делегата как можно раньше, до доставки любого уведомления.
        // Без него foreground-уведомления подавляются системой.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

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
                    // При первом активном фрейме — запрашиваем разрешение,
                    // чтобы iOS показал системный алерт и приложение появилось
                    // в Settings → Notifications. _Requirements: 5.1_
                    Task { @MainActor in
                        if !didRequestAuthorizationOnStart {
                            didRequestAuthorizationOnStart = true
                            let status = await scheduler.refreshAuthorizationStatus()
                            if status == .notDetermined {
                                await scheduler.requestAuthorization()
                            }
                        } else {
                            await scheduler.refreshAuthorizationStatus()
                        }
                        // _Requirements: 5.7, 5.8, 7.11_
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
