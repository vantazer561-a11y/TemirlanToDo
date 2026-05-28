import SwiftUI
import UIKit

/// Экран настроек уведомлений: включение/выключение утреннего сводного и
/// точечных напоминаний, выбор времени и lead-time. Все мутации проходят
/// через `NotificationSettingsStore`, после успешного сохранения вызывается
/// `NotificationScheduler.synchronize` для пересинхронизации pending-запросов.
/// _Requirements: 5.1-5.5, 8.1-8.10_
struct NotificationSettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var settingsStore: NotificationSettingsStore
    @EnvironmentObject private var scheduler: NotificationScheduler

    @State private var saveError: String?

    var body: some View {
        Form {
            if scheduler.authorizationState == .denied {
                Section {
                    Text("Разрешение на уведомления отключено")
                        .foregroundColor(CyberpunkTheme.magenta)
                    Button("Открыть настройки iOS") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }

            Section("Утреннее сводное") {
                Toggle(
                    "Morning summary",
                    isOn: Binding(
                        get: { settingsStore.settings.morningDigestEnabled },
                        set: { newValue in
                            updateSettings { $0.morningDigestEnabled = newValue }
                        }
                    )
                )
                .disabled(scheduler.authorizationState == .denied)

                if settingsStore.settings.morningDigestEnabled {
                    DatePicker(
                        "Время",
                        selection: Binding(
                            get: { dateFromTimeOfDay(settingsStore.settings.morningTime) },
                            set: { newDate in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                updateSettings {
                                    $0.morningTime = TimeOfDay(
                                        hour: comps.hour ?? 8,
                                        minute: comps.minute ?? 0
                                    )
                                }
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }
            }

            Section("Напоминания о задачах") {
                Toggle(
                    "Task reminders",
                    isOn: Binding(
                        get: { settingsStore.settings.taskRemindersEnabled },
                        set: { newValue in
                            updateSettings { $0.taskRemindersEnabled = newValue }
                        }
                    )
                )
                .disabled(scheduler.authorizationState == .denied)

                if settingsStore.settings.taskRemindersEnabled {
                    Picker(
                        "За сколько до",
                        selection: Binding(
                            get: { settingsStore.settings.leadTimeMinutes },
                            set: { newValue in
                                updateSettings { _ = $0.setLeadTime(newValue) }
                            }
                        )
                    ) {
                        ForEach(NotificationSettings.allowedLeadTimes, id: \.self) { v in
                            Text("\(v) мин").tag(v)
                        }
                    }
                }
            }

            if let saveError {
                Section {
                    Text(saveError).foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Уведомления")
        .task {
            if scheduler.authorizationState == .notDetermined {
                await scheduler.requestAuthorization()
            } else {
                await scheduler.refreshAuthorizationStatus()
            }
        }
    }

    private func dateFromTimeOfDay(_ time: TimeOfDay) -> Date {
        var comps = DateComponents()
        comps.hour = time.hour
        comps.minute = time.minute
        return Calendar.current.date(from: comps) ?? Date()
    }

    /// Сохраняет изменения через `NotificationSettingsStore` и затем
    /// триггерит пересинхронизацию pending-запросов. Если разрешение ещё не
    /// запрошено — сначала запросить (Req 5.2). Сохранение ошибки выводится
    /// в `saveError` без изменения in-memory `settings`.
    /// _Requirements: 5.2, 5.3, 8.8, 8.9_
    private func updateSettings(_ transform: @escaping (inout NotificationSettings) -> Void) {
        Task {
            if scheduler.authorizationState == .notDetermined {
                await scheduler.requestAuthorization()
                if scheduler.authorizationState != .authorized {
                    return
                }
            }

            let ok = settingsStore.update { state in
                transform(&state)
                return true
            }
            if !ok {
                saveError = "Не удалось сохранить настройку"
                return
            }
            saveError = nil
            await scheduler.synchronize(with: store.tasks, settings: settingsStore.settings)
        }
    }
}
