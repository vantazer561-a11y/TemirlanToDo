# Technical Design: task-time-and-notifications

## Overview

Фича расширяет TemirlanToDo (SwiftUI, iOS 15+) тремя связанными слоями:

1. **Модель** — `TaskItem` получает поле `dueHasTime: Bool`. JSON-схема сохраняется, обратная совместимость держится через кастомный `init(from decoder:)`.
2. **Локальные уведомления** — новый сервис `NotificationScheduler` (App-таргет) поверх `UNUserNotificationCenter`, новая модель `NotificationSettings` в `UserDefaults` суиты App Group, новый экран `NotificationSettingsView`.
3. **Виджет** — `TodayWidgetSnapshot` дополняется опциональными полями `nextTimedTitle` и `nextTimedDate`, виджет рендерит строку «Next: …». Существующие сборки виджета продолжают читать снапшот без ошибок (нет мажорной миграции).

Цель — внести минимальные изменения в существующий стек (`TaskStore` остаётся single source of truth, без Combine-революций), добавить уведомления так, чтобы их синхронизация была идемпотентной и шла через одну точку — `NotificationScheduler.synchronize(with:settings:)`.

Никакого нового entitlement не требуется (App Group уже подключена, локальные уведомления entitlement не требуют). `UNUserNotificationsUsageDescription` в Info.plist не нужен — это разрешение iOS показывает системным алертом без описания. Нужен только запрос `UNUserNotificationCenter.current().requestAuthorization(options:)`. Background mode тоже не нужен — все уведомления локальные, планируются через `UNCalendarNotificationTrigger` и доставляются системой, приложение не должно работать в фоне.

## Architecture

### Высокоуровневая схема

```mermaid
flowchart TD
    User[User UI events] --> RootView
    RootView --> NotificationSettingsView
    RootView --> TaskListView
    TaskListView --> TaskDetailView
    TaskListView --> AddTaskComposerView

    TaskDetailView -->|updateTask| TaskStore
    AddTaskComposerView -->|addTask| TaskStore
    AssistantService -->|applyAssistantActions| TaskStore

    TaskStore -->|@Published tasks| Subscribers
    TaskStore -->|save| TaskStorage
    TaskStore -->|saveTodayWidgetSnapshot| TodayWidgetSnapshotStore
    TaskStore -->|notifyChange| NotificationScheduler

    NotificationSettingsView -->|read/write| NotificationSettings
    NotificationSettings -->|@AppStorage / UserDefaults| AppGroupDefaults

    NotificationScheduler -->|UNUserNotificationCenter| iOS
    iOS -->|deliver| UserDevice

    TodayWidgetSnapshotStore -->|App Group| WidgetExtension
    WidgetExtension --> TemirlanToDoWidget
```

### Поток событий «изменение задачи → уведомления → виджет»

1. Пользователь/AI меняет задачу через `TaskStore` (`addTask`, `updateTask`, `toggleCompletion`, `applyAssistantActions`, `deleteTask`).
2. `TaskStore.save()` — единая точка после любой мутации:
   - сериализует `[TaskItem]` через `TaskStorage`;
   - вычисляет и сохраняет `TodayWidgetSnapshot` (включая `nextTimedTitle`/`nextTimedDate`) в App Group;
   - вызывает `NotificationScheduler.synchronize(with: tasks, settings: NotificationSettings.current)` (на background-очереди).
3. `NotificationScheduler.synchronize(with:settings:)` — идемпотентный пересчёт:
   - получает `getNotificationSettings` из `UNUserNotificationCenter`;
   - если `authorizationStatus != .authorized` → отменяет всё и выходит;
   - иначе строит целевое множество запросов (1 утренний + N task-reminder), сравнивает с текущим `getPendingNotificationRequests`, удаляет лишние и добавляет недостающие.
4. WidgetKit получает `WidgetCenter.shared.reloadTimelines(ofKind:)` (вызывается ровно один раз внутри `TodayWidgetSnapshotStore.save`).

### Жизненный цикл уведомлений (`scenePhase`)

В `TemirlanToDoApp`:
- На первом `WindowGroup.body` подписываемся на `@Environment(\.scenePhase)`.
- При переходе в `.active`:
  - `NotificationScheduler.refreshAuthorizationStatus()` — обновляет кешированный `Permission_State`;
  - `NotificationScheduler.synchronize(with: store.tasks, settings: settings)` — пересинхронизация (нужно, потому что pending-уведомления могут быть очищены системой, а пользователь мог сменить разрешение в Настройках iOS).
- Запрос `requestAuthorization` НЕ делается на старте автоматически. Запрашивается только из `NotificationSettingsView` (либо при первом открытии экрана, если статус `.notDetermined`, либо при включении любого тумблера).

### Хранилище `NotificationSettings`

`NotificationSettings` хранится двумя путями:
- **Основной**: `UserDefaults(suiteName: "group.com.temirlan.todo")` — нужен, потому что виджет в будущем может читать те же настройки и потому что App Group у проекта уже подключена.
- **Fallback**: `UserDefaults.standard`, если по какой-то причине App-Group-suite вернул `nil`.

Ключ: `notification_settings`. Сериализация — `JSONEncoder/JSONDecoder` на `NotificationSettings` (Codable). Доступ инкапсулирован в `NotificationSettingsStore`.

### Изменения в данных и миграция

- `TaskItem` получает `public var dueHasTime: Bool`. Кастомный `init(from:)` декодирует JSON без ключа `dueHasTime` как `false`. Если `dueDate == nil`, значение `dueHasTime` принудительно `false` (инвариант хранилища).
- `TodayWidgetSnapshot` получает `nextTimedTitle: String?` и `nextTimedDate: Date?`. Поскольку оба опциональные и Swift Codable для опциональных по умолчанию допускает отсутствие ключа, ничего дополнительно делать не требуется — старые снапшоты декодируются с `nil` в новых полях.
- Миграция JSON задач: при первом сохранении после обновления `JSONEncoder` запишет ключ `dueHasTime: false` для всех загруженных без этого ключа задач. Никаких форсированных миграций — лениво.

### iOS-лимит 64 pending notifications

`NotificationScheduler.rescheduleTaskReminders(...)`:
1. Сортирует кандидатов (Timed, не выполненных, `dueDate − leadTime > now`) по возрастанию `dueDate`.
2. Берёт первые `min(count, 64 - reservedSlots)`, где `reservedSlots = morningDigestEnabled ? 1 : 0`.
3. Лишние не планируются. Лог через `os_log` для диагностики, без user-facing ошибки.

## Components and Interfaces

### Структура файлов

**Создаются:**
- `TemirlanToDo/Notifications/NotificationScheduler.swift`
- `TemirlanToDo/Notifications/NotificationSettings.swift`
- `TemirlanToDo/Notifications/NotificationCenterProtocol.swift`
- `TemirlanToDo/Views/NotificationSettingsView.swift`
- `TemirlanToDoTests/TaskItemMigrationTests.swift`
- `TemirlanToDoTests/NotificationSettingsTests.swift`
- `TemirlanToDoTests/NotificationSchedulerTests.swift`
- `TemirlanToDoTests/TodayWidgetSnapshotTests.swift`

**Изменяются:**
- `TemirlanToDo/Models/TaskItem.swift` — поле `dueHasTime`, кастомный `init(from:)`, кастомный `encode(to:)` для стабильного порядка ключей.
- `TemirlanToDo/Models/TodayWidgetSnapshot.swift` — поля `nextTimedTitle`, `nextTimedDate`.
- `TemirlanToDo/Stores/TaskStore.swift` — `applyAssistantActions` поддерживает оба формата `dueDate`, `saveTodayWidgetSnapshot` вычисляет `nextTimed*`, `save()` дёргает `NotificationScheduler.synchronize`, новые методы `setDueDate(_:hasTime:for:)`, `clearDueDate(for:)`.
- `TemirlanToDo/TemirlanToDoApp.swift` — `@StateObject NotificationScheduler`, `@StateObject NotificationSettingsStore`, обработка `scenePhase`.
- `TemirlanToDo/Views/RootView.swift` — кнопка-колокольчик в навигационной панели → `NotificationSettingsView`.
- `TemirlanToDo/Views/TaskDetailView.swift` — тумблер `Add time` + `DatePicker(displayedComponents: .hourAndMinute)`.
- `TemirlanToDo/Views/AddTaskComposerView.swift` — без изменений в композере, но `addTask` остаётся быстрым (без времени). Время задаётся в `TaskDetailView`.
- `TemirlanToDo/Views/TaskRowView.swift` — формат «дата» / «дата, время» в зависимости от `dueHasTime`.
- `TemirlanToDo/AI/AssistantModels.swift` — `AssistantSchema.json`: тип `dueDate` становится строкой одного из двух форматов либо `null`.
- `TemirlanToDo/AI/AssistantService.swift` — `developerPrompt` упоминает оба формата.
- `TemirlanToDo/AI/FireworksClient.swift` — system-промпт упоминает оба формата (синхронно с developerPrompt).
- `TemirlanToDoWidget/TemirlanToDoWidget.swift` — локальное `TodayWidgetSnapshot` дублируется (виджет читает свой Codable, чтобы не зависеть от App-таргета): добавляются `nextTimedTitle`, `nextTimedDate`, в UI — строка «Next: …».
- `TemirlanToDo/Info.plist` — без изменений (никаких новых ключей не нужно).
- `TemirlanToDo.xcodeproj/project.pbxproj` — новые файлы добавляются в `TemirlanToDo` target и/или `TemirlanToDoTests` target.

### `NotificationCenterProtocol`

Узкий протокол поверх `UNUserNotificationCenter` для тестируемости.

```swift
import UserNotifications

protocol NotificationCenterProtocol: AnyObject {
    func getNotificationSettings() async -> UNNotificationSettings
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
}

extension UNUserNotificationCenter: NotificationCenterProtocol {
    func getNotificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { cont in
            getNotificationSettings { cont.resume(returning: $0) }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            add(request) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { cont in
            getPendingNotificationRequests { cont.resume(returning: $0) }
        }
    }
}
```

В тестах `UNNotificationSettings` мокается через подтип, либо мок возвращает заранее сконфигурированный fake (см. Testing Strategy).

### `NotificationScheduler`

Файл `TemirlanToDo/Notifications/NotificationScheduler.swift`.

```swift
import Foundation
import UserNotifications
import os.log

@MainActor
public final class NotificationScheduler: ObservableObject {
    public enum AuthorizationState: Equatable {
        case notDetermined
        case authorized
        case denied
        case provisional
        case ephemeral
    }

    @Published public private(set) var authorizationState: AuthorizationState = .notDetermined

    public static let pendingRequestLimit = 64
    public static let morningDigestId = "morning-digest"
    public static func taskReminderId(for taskId: UUID) -> String {
        "task-reminder.\(taskId.uuidString)"
    }

    private let center: NotificationCenterProtocol
    private let calendar: Calendar
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.temirlan.todo", category: "Notifications")

    public init(
        center: NotificationCenterProtocol = UNUserNotificationCenter.current(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.center = center
        self.calendar = calendar
        self.now = now
    }

    @discardableResult
    public func requestAuthorization() async -> AuthorizationState {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("requestAuthorization failed: \(error.localizedDescription, privacy: .public)")
        }
        return await refreshAuthorizationStatus()
    }

    @discardableResult
    public func refreshAuthorizationStatus() async -> AuthorizationState {
        let settings = await center.getNotificationSettings()
        let state = AuthorizationState(settings.authorizationStatus)
        self.authorizationState = state
        return state
    }

    /// Главная idempotent-операция: применяет целевое состояние.
    public func synchronize(with tasks: [TaskItem], settings: NotificationSettings) async {
        let state = await refreshAuthorizationStatus()
        guard state == .authorized || state == .provisional else {
            await cancelAll()
            return
        }
        await rescheduleAll(tasks: tasks, settings: settings)
    }

    public func rescheduleAll(tasks: [TaskItem], settings: NotificationSettings) async {
        await rescheduleMorningDigest(tasks: tasks, settings: settings)
        await rescheduleTaskReminders(tasks: tasks, settings: settings)
    }

    public func cancel(for taskId: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.taskReminderId(for: taskId)])
    }

    public func cancelAll() async {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Morning digest

    func rescheduleMorningDigest(tasks: [TaskItem], settings: NotificationSettings) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.morningDigestId])
        guard settings.morningDigestEnabled else { return }

        let activeToday = tasksActiveToday(in: tasks)
        guard !activeToday.isEmpty else {
            // По требованию 6.3 не показываем уведомление, если задач нет.
            return
        }

        let content = UNMutableNotificationContent()
        content.title = morningTitle(activeCount: activeToday.count)
        content.body = morningBody(activeToday: activeToday)
        content.sound = .default

        var trigger = DateComponents()
        trigger.hour = settings.morningTime.hour
        trigger.minute = settings.morningTime.minute

        let request = UNNotificationRequest(
            identifier: Self.morningDigestId,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: true)
        )
        try? await center.add(request)
    }

    // MARK: - Task reminders

    func rescheduleTaskReminders(tasks: [TaskItem], settings: NotificationSettings) async {
        let pending = await center.pendingNotificationRequests()
        let existingTaskReminderIds = Set(
            pending.map(\.identifier).filter { $0.hasPrefix("task-reminder.") }
        )
        center.removePendingNotificationRequests(withIdentifiers: Array(existingTaskReminderIds))

        guard settings.taskRemindersEnabled else { return }

        let lead = TimeInterval(settings.leadTimeMinutes * 60)
        let now = self.now()
        let candidates = tasks
            .filter { !$0.isCompleted && $0.dueHasTime && $0.dueDate != nil }
            .filter { ($0.dueDate!.timeIntervalSince(now)) > lead }
            .sorted { $0.dueDate! < $1.dueDate! }

        let reservedForMorning = settings.morningDigestEnabled ? 1 : 0
        let allowed = max(0, Self.pendingRequestLimit - reservedForMorning)
        let toSchedule = candidates.prefix(allowed)

        for task in toSchedule {
            await scheduleTaskReminder(for: task, leadTime: settings.leadTimeMinutes)
        }
        if candidates.count > toSchedule.count {
            logger.info("Skipped \(candidates.count - toSchedule.count) task reminders due to 64 pending limit")
        }
    }

    func scheduleTaskReminder(for task: TaskItem, leadTime: Int) async {
        guard let due = task.dueDate, task.dueHasTime else { return }
        let fireDate = due.addingTimeInterval(-Double(leadTime) * 60)
        guard fireDate > now() else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = taskReminderBody(due: due, leadMinutes: leadTime)
        content.sound = .default

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(
            identifier: Self.taskReminderId(for: task.id),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )
        try? await center.add(request)
    }

    // MARK: - Body builders (visible for tests via @testable)

    func morningTitle(activeCount n: Int) -> String {
        "Сегодня \(n) \(russianTaskWord(for: n))"
    }

    func morningBody(activeToday: [TaskItem]) -> String {
        if let next = nextTimedTaskToday(in: activeToday) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "HH:mm"
            return "Ближайшая: \(next.title) в \(f.string(from: next.dueDate!))"
        }
        if let nearest = nearestActiveTask(in: activeToday) {
            return "Ближайшая: \(nearest.title)"
        }
        return ""
    }

    func taskReminderBody(due: Date, leadMinutes: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return "Через \(leadMinutes) мин в \(f.string(from: due))"
    }

    /// Русское склонение для слова «задача».
    static func russianTaskWord(for n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if (11...14).contains(mod100) { return "задач" }
        if mod10 == 1 { return "задача" }
        if (2...4).contains(mod10) { return "задачи" }
        return "задач"
    }

    private func russianTaskWord(for n: Int) -> String { Self.russianTaskWord(for: n) }
}
```

Вспомогательные функции (`tasksActiveToday`, `nextTimedTaskToday`, `nearestActiveTask`) живут в том же файле и являются `internal` для тестируемости через `@testable import`.

### `NotificationSettings` и `NotificationSettingsStore`

Файл `TemirlanToDo/Notifications/NotificationSettings.swift`.

```swift
import Foundation
import Combine

public struct NotificationSettings: Codable, Equatable {
    public static let allowedLeadTimes: [Int] = [5, 15, 30, 60]

    public var morningDigestEnabled: Bool
    public var morningTime: TimeOfDay   // hour: 0..23, minute: 0..59
    public var taskRemindersEnabled: Bool
    public var leadTimeMinutes: Int

    public static let `default` = NotificationSettings(
        morningDigestEnabled: true,
        morningTime: TimeOfDay(hour: 8, minute: 0),
        taskRemindersEnabled: true,
        leadTimeMinutes: 15
    )

    /// Валидирует и нормализует значения; вне допустимых диапазонов поля не меняются.
    public mutating func setLeadTime(_ value: Int) -> Bool {
        guard NotificationSettings.allowedLeadTimes.contains(value) else { return false }
        leadTimeMinutes = value
        return true
    }
}

public struct TimeOfDay: Codable, Equatable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }
}

public final class NotificationSettingsStore: ObservableObject {
    private static let key = "notification_settings"
    public static let appGroupIdentifier = "group.com.temirlan.todo"

    @Published public private(set) var settings: NotificationSettings

    private let defaults: UserDefaults
    private let fallback: UserDefaults

    public init(
        defaults: UserDefaults? = UserDefaults(suiteName: NotificationSettingsStore.appGroupIdentifier),
        fallback: UserDefaults = .standard
    ) {
        self.defaults = defaults ?? fallback
        self.fallback = fallback
        self.settings = Self.load(defaults: self.defaults, fallback: fallback)
    }

    public func update(_ transform: (inout NotificationSettings) -> Bool) -> Bool {
        var next = settings
        guard transform(&next) else { return false }
        return save(next)
    }

    @discardableResult
    public func save(_ next: NotificationSettings) -> Bool {
        guard let data = try? JSONEncoder().encode(next) else { return false }
        defaults.set(data, forKey: Self.key)
        settings = next
        return true
    }

    static func load(defaults: UserDefaults, fallback: UserDefaults) -> NotificationSettings {
        let data = defaults.data(forKey: key) ?? fallback.data(forKey: key)
        guard
            let data,
            let decoded = try? JSONDecoder().decode(NotificationSettings.self, from: data),
            isValid(decoded)
        else {
            return .default
        }
        return decoded
    }

    static func isValid(_ s: NotificationSettings) -> Bool {
        (0...23).contains(s.morningTime.hour) &&
        (0...59).contains(s.morningTime.minute) &&
        NotificationSettings.allowedLeadTimes.contains(s.leadTimeMinutes)
    }
}
```

### `NotificationSettingsView`

Файл `TemirlanToDo/Views/NotificationSettingsView.swift`. Минимальный интерфейс:

```swift
import SwiftUI
import UIKit

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
                Toggle("Morning summary", isOn: morningEnabledBinding)
                    .disabled(scheduler.authorizationState == .denied)
                if settingsStore.settings.morningDigestEnabled {
                    DatePicker(
                        "Время",
                        selection: morningTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                }
            }

            Section("Напоминания о задачах") {
                Toggle("Task reminders", isOn: taskRemindersBinding)
                    .disabled(scheduler.authorizationState == .denied)
                if settingsStore.settings.taskRemindersEnabled {
                    Picker("За сколько до", selection: leadTimeBinding) {
                        ForEach(NotificationSettings.allowedLeadTimes, id: \.self) { v in
                            Text("\(v) мин").tag(v)
                        }
                    }
                }
            }

            if let saveError {
                Section { Text(saveError).foregroundColor(.red) }
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

    // Биндинги выполняют request-on-toggle и сохранение через store.
    // При неудачном save — saveError выставляется, settingsStore не меняется.
    // ...
}
```

Каждый биндинг делает: при `notDetermined` → `await scheduler.requestAuthorization()`; при `authorized`/`provisional` → `settingsStore.save(next)`; при ошибке сохранения — `saveError = ...`, без изменения in-memory `settings`. После успешного сохранения вызывает `Task { await scheduler.synchronize(with: store.tasks, settings: settingsStore.settings) }`.

### Изменения `TaskItem`

```swift
public struct TaskItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var isCompleted: Bool
    public var isImportant: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var dueDate: Date?
    public var dueHasTime: Bool          // НОВОЕ
    public var isInMyDay: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        isCompleted: Bool = false,
        isImportant: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        dueDate: Date? = nil,
        dueHasTime: Bool = false,
        isInMyDay: Bool = false
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.isImportant = isImportant
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueDate = dueDate
        self.dueHasTime = (dueDate == nil) ? false : dueHasTime
        self.isInMyDay = isInMyDay
    }

    enum CodingKeys: String, CodingKey {
        case id, title, notes, isCompleted, isImportant
        case createdAt, updatedAt, dueDate, dueHasTime, isInMyDay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let title = try c.decode(String.self, forKey: .title)
        let notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        let isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        let isImportant = try c.decodeIfPresent(Bool.self, forKey: .isImportant) ?? false
        let createdAt = try c.decode(Date.self, forKey: .createdAt)
        let updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        let dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        let rawHasTime = try c.decodeIfPresent(Bool.self, forKey: .dueHasTime) ?? false
        let dueHasTime = (dueDate == nil) ? false : rawHasTime
        let isInMyDay = try c.decodeIfPresent(Bool.self, forKey: .isInMyDay) ?? false

        self.init(
            id: id, title: title, notes: notes,
            isCompleted: isCompleted, isImportant: isImportant,
            createdAt: createdAt, updatedAt: updatedAt,
            dueDate: dueDate, dueHasTime: dueHasTime, isInMyDay: isInMyDay
        )
    }
}
```

`encode(to:)` идёт по умолчанию (synthesized) — пишет все ключи, включая `dueHasTime`.

### Изменения `TaskStore.applyAssistantActions`

```swift
private static let isoDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

private static let isoDateTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return f
}()

/// Возвращает (Date?, hasTime, validationOk).
/// Если строка не nil, не пустая, но не парсится ни одним форматом — validationOk == false.
private func parseAssistantDueDate(_ value: String?, calendar: Calendar) -> (Date?, Bool, Bool) {
    guard let value, !value.isEmpty else { return (nil, false, true) }
    var f1 = Self.isoDateFormatter; f1.calendar = calendar; f1.timeZone = calendar.timeZone
    if let d = f1.date(from: value) { return (d, false, true) }
    var f2 = Self.isoDateTimeFormatter; f2.calendar = calendar; f2.timeZone = calendar.timeZone
    if let d = f2.date(from: value) { return (d, true, true) }
    return (nil, false, false)
}
```

В `applyAssistantActions` вместо текущего `tasks[index].dueDate = date(from: action.dueDate, calendar: calendar)` — раздельная обработка двух форматов и установка `dueHasTime`. При невалидной строке: задача не меняется по `dueDate`/`dueHasTime`, выставляется `lastErrorMessage = "AI вернул некорректный формат даты"`, цикл не прерывается.

Поскольку в `AssistantAction` поле `dueDate` сейчас `String?` со семантикой «`nil` = не трогать, не-nil = заменить (включая null от модели)», важно сохранить эту семантику. JSON `null` от модели декодируется в `Optional.none`, что трактуется как «не трогать». Но требование 4.4 говорит: `dueDate == null` → задача очищается. Решение: добавить второй сигнальный флаг через расширение схемы — `clearsDueDate` НЕ вводим, чтобы не плодить полей. Вместо этого **меняем семантику отсутствующего ключа на «не трогать», а явный JSON `null` на «очистить»**, реализуя через `decodeIfPresent` с проверкой `contains(.dueDate)` в кастомном `init(from:)` `AssistantAction`:

```swift
public struct AssistantAction: Codable, Identifiable, Equatable {
    // ... поля как раньше плюс:
    public private(set) var dueDateProvided: Bool   // true если ключ присутствовал в JSON
    public var dueDate: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // ...остальные поля...
        self.dueDateProvided = c.contains(.dueDate)
        self.dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
    }
}
```

В `applyAssistantActions` для `updateTask`:
- если `action.dueDateProvided == false` → не трогаем `dueDate`/`dueHasTime`;
- если `dueDateProvided == true` и `dueDate == nil` → `dueDate = nil`, `dueHasTime = false`;
- если `dueDateProvided == true` и `dueDate != nil` → парсим, по результату — обновляем оба поля или фиксируем ошибку.

Для `createTask` — ключ присутствует или нет, не важно: если `dueDate == nil` или отсутствует — задача создаётся без даты.

### Изменения `TodayWidgetSnapshot`

```swift
public struct TodayWidgetSnapshot: Codable, Equatable {
    public var count: Int
    public var titles: [String]
    public var updatedAt: Date
    public var nextTimedTitle: String?      // НОВОЕ
    public var nextTimedDate: Date?         // НОВОЕ

    public init(
        count: Int,
        titles: [String],
        updatedAt: Date = Date(),
        nextTimedTitle: String? = nil,
        nextTimedDate: Date? = nil
    ) {
        self.count = count
        self.titles = titles
        self.updatedAt = updatedAt
        self.nextTimedTitle = nextTimedTitle
        self.nextTimedDate = nextTimedDate
    }

    public static let empty = TodayWidgetSnapshot(count: 0, titles: [])
}
```

Synthesized Codable: для опциональных полей отсутствие ключа в JSON корректно декодируется в `nil`. Для виджета (отдельный файл `TemirlanToDoWidget/TemirlanToDoWidget.swift`) добавляем те же поля локально.

### Изменения `TaskStore.saveTodayWidgetSnapshot`

```swift
private func saveTodayWidgetSnapshot(calendar: Calendar = .current, now: Date = Date()) {
    let active = tasks.filter { !$0.isCompleted && TaskListKind.myDay.contains($0, calendar: calendar, now: now) }
    let titles = Array(active.prefix(3)).map(\.title)

    let nextTimed = active
        .filter { $0.dueHasTime && $0.dueDate != nil }
        .filter { calendar.isDate($0.dueDate!, inSameDayAs: now) && $0.dueDate! >= now }
        .sorted { lhs, rhs in
            if lhs.dueDate! != rhs.dueDate! { return lhs.dueDate! < rhs.dueDate! }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        .first

    let snapshot = TodayWidgetSnapshot(
        count: active.count,
        titles: titles,
        nextTimedTitle: nextTimed.map { String($0.title.prefix(80)) },
        nextTimedDate: nextTimed?.dueDate
    )
    TodayWidgetSnapshotStore.save(snapshot)
}
```

`TodayWidgetSnapshotStore.save` уже вызывает `WidgetCenter.shared.reloadTimelines(...)` ровно один раз — менять не нужно.

### Изменения `TaskDetailView`

```swift
@State private var draft: TaskItem
@State private var hasDueDate: Bool
@State private var hasDueTime: Bool

init(task: TaskItem) {
    _draft = State(initialValue: task)
    _hasDueDate = State(initialValue: task.dueDate != nil)
    _hasDueTime = State(initialValue: task.dueHasTime)
}
```

В `Section("Signals")`:

```swift
Toggle("Due date", isOn: $hasDueDate)
    .onChange(of: hasDueDate) { isOn in
        if isOn {
            if draft.dueDate == nil {
                draft.dueDate = Calendar.current.startOfDay(for: Date())
                draft.dueHasTime = false
                hasDueTime = false
            }
        } else {
            draft.dueDate = nil
            draft.dueHasTime = false
            hasDueTime = false
        }
    }

if hasDueDate {
    DatePicker(
        "Date",
        selection: Binding(
            get: { draft.dueDate ?? Date() },
            set: { draft.dueDate = $0 }
        ),
        displayedComponents: .date
    )
}

Toggle("Add time", isOn: $hasDueTime)
    .disabled(!hasDueDate)
    .onChange(of: hasDueTime) { isOn in
        if isOn {
            draft.dueDate = nextRoundedQuarterHour(after: Date(), base: draft.dueDate)
            draft.dueHasTime = true
        } else {
            if let due = draft.dueDate {
                draft.dueDate = Calendar.current.startOfDay(for: due)
            }
            draft.dueHasTime = false
        }
    }

if hasDueDate && hasDueTime {
    DatePicker(
        "Time",
        selection: Binding(
            get: { draft.dueDate ?? Date() },
            set: { draft.dueDate = $0 }
        ),
        displayedComponents: .hourAndMinute
    )
}
```

`nextRoundedQuarterHour(after:base:)` — internal helper в том же файле, чтобы тестировать (логика сложная: ближайший в будущем момент с минутами кратно 15, секунды/наносекунды = 0; если ближайший попадает на следующий день, дата сдвигается; календарная дата `dueDate` имеет приоритет, но если она «сегодня», ровняем по `now`).

### Изменения `TaskRowView`

```swift
if let dueDate = task.dueDate {
    let label = formattedDue(dueDate: dueDate, hasTime: task.dueHasTime)
    Label(label, systemImage: "calendar")
}

private func formattedDue(dueDate: Date, hasTime: Bool) -> String {
    let f = DateFormatter()
    f.locale = .current
    f.timeZone = .current
    f.dateStyle = .short
    f.timeStyle = hasTime ? .short : .none
    return f.string(from: dueDate)
}
```

`DateFormatter.short` + `timeStyle = .short` даёт «27.05.26, 14:30» в ru и «5/27/26, 2:30 PM» в en. Перерисовку при смене таймзоны/локали обеспечивает SwiftUI через `@Environment(\.locale)` и автоматическое обновление `body` при изменении. Делаем `private struct DueLabel: View` с `@Environment(\.locale) var locale` и `@Environment(\.timeZone) var ...` — на iOS нет `\.timeZone` в Environment, но `DateFormatter` использует `.current`, а SwiftUI пересобирает `body` на изменении системной локали, что инициируется самим SwiftUI runtime.

### Изменения `RootView`

В шапке навигационной панели — кнопка-колокольчик:

```swift
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        NavigationLink(destination: NotificationSettingsView()) {
            Image(systemName: "bell.fill").foregroundColor(CyberpunkTheme.cyan)
        }
    }
}
```

И снимаем `.navigationBarHidden(true)` (или показываем custom toolbar).

### Изменения `TemirlanToDoApp`

```swift
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
                    LaunchSplashView(isVisible: $showingSplash).transition(.opacity)
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    Task {
                        await scheduler.refreshAuthorizationStatus()
                        await scheduler.synchronize(with: store.tasks, settings: settingsStore.settings)
                    }
                }
            }
        }
    }
}
```

`TaskStore.save()` дополнительно вызывает синхронизацию (без ожидания):

```swift
public func save() {
    do {
        try storage.saveTasks(tasks)
        saveTodayWidgetSnapshot()
        lastErrorMessage = nil
        notifySchedulerNeedsSync?()    // optional closure injection, dependency-free
    } catch {
        lastErrorMessage = "Could not save the latest changes."
    }
}

public var notifySchedulerNeedsSync: (() -> Void)?
```

В `TemirlanToDoApp` после `StateObject` инициализации:

```swift
.onAppear {
    let scheduler = scheduler
    let settingsStore = settingsStore
    store.notifySchedulerNeedsSync = { [weak store] in
        guard let store else { return }
        Task { await scheduler.synchronize(with: store.tasks, settings: settingsStore.settings) }
    }
}
```

### Изменения AI: `AssistantSchema.json`

```swift
"dueDate": [
    "type": ["string", "null"],
    "description": "ISO date in 'yyyy-MM-dd' or ISO date-time in 'yyyy-MM-dd'T'HH:mm' format (local timezone). null clears the due date.",
    "pattern": "^(\\d{4}-\\d{2}-\\d{2}(T\\d{2}:\\d{2})?)$"
]
```

В `AssistantService.developerPrompt` и `FireworksClient.requestBody` — синхронизированный текст: «Use dueDate as `yyyy-MM-dd` (date only, no time) or `yyyy-MM-dd'T'HH:mm` (with local time). Use `null` to clear due date».

### Изменения `TemirlanToDoWidget`

Локальный `TodayWidgetSnapshot` копируется и расширяется теми же двумя полями. В `TodayTasksWidgetView`:

```swift
if let title = entry.snapshot.nextTimedTitle, let date = entry.snapshot.nextTimedDate {
    let f: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
    HStack(spacing: 6) {
        Image(systemName: "alarm")
            .foregroundColor(CyberpunkTheme.amber)   // если виджет имеет доступ; иначе hardcoded color
        Text("Next: \(title) в \(f.string(from: date))")
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white.opacity(0.9))
            .lineLimit(1)
    }
}
```

`CyberpunkTheme` принадлежит App-таргету — для виджета берём hardcoded color вроде `Color(red: 1.0, green: 0.78, blue: 0.0)` (amber). Расположение строки — после текущего блока с заголовками.

## Data Models

### `TaskItem` (изменено)

| Поле | Тип | Дефолт | Семантика |
|---|---|---|---|
| `id` | `UUID` | `UUID()` | без изменений |
| `title` | `String` | — | без изменений |
| `notes` | `String` | `""` | без изменений |
| `isCompleted` | `Bool` | `false` | без изменений |
| `isImportant` | `Bool` | `false` | без изменений |
| `createdAt` | `Date` | `Date()` | без изменений |
| `updatedAt` | `Date` | `Date()` | без изменений |
| `dueDate` | `Date?` | `nil` | момент в `Date`. Если `dueHasTime == false` — нормализован к началу локального дня. Если `true` — точный момент с обнулёнными секундами/наносекундами |
| `dueHasTime` | `Bool` | `false` | **новое**. Если `dueDate == nil`, всегда `false` |
| `isInMyDay` | `Bool` | `false` | без изменений |

JSON-формат (пример):

```json
{
  "id": "...",
  "title": "...",
  "notes": "",
  "isCompleted": false,
  "isImportant": false,
  "createdAt": 769900000.0,
  "updatedAt": 769900000.0,
  "dueDate": 769986600.0,
  "dueHasTime": true,
  "isInMyDay": false
}
```

Старые JSON без ключа `dueHasTime` декодируются с `dueHasTime = false`.

### `NotificationSettings` (новая)

| Поле | Тип | Дефолт | Валидация |
|---|---|---|---|
| `morningDigestEnabled` | `Bool` | `true` | — |
| `morningTime.hour` | `Int` | `8` | `0..23` |
| `morningTime.minute` | `Int` | `0` | `0..59` |
| `taskRemindersEnabled` | `Bool` | `true` | — |
| `leadTimeMinutes` | `Int` | `15` | `∈ {5, 15, 30, 60}` |

Хранение: `UserDefaults(suiteName: "group.com.temirlan.todo")`, ключ `notification_settings`, JSON-encoded.

### `TodayWidgetSnapshot` (расширено)

| Поле | Тип | Дефолт | Семантика |
|---|---|---|---|
| `count` | `Int` | `0` | активных задач сегодня |
| `titles` | `[String]` | `[]` | первые 3 заголовка |
| `updatedAt` | `Date` | `Date()` | момент сохранения |
| `nextTimedTitle` | `String?` | `nil` | **новое**. Заголовок Next_Timed_Task_Today, обрезан до 80 символов без многоточия |
| `nextTimedDate` | `Date?` | `nil` | **новое**. `dueDate` Next_Timed_Task_Today |

### Идентификаторы уведомлений

| Тип | Идентификатор | Trigger |
|---|---|---|
| Morning digest | `morning-digest` | `UNCalendarNotificationTrigger(dateMatching: {hour, minute}, repeats: true)` |
| Task reminder | `task-reminder.<UUID>` | `UNCalendarNotificationTrigger(dateMatching: full components of fireDate, repeats: false)` |


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

PBT здесь применима: ядро фичи — чистые функции (парсер `dueDate`, форматтеры, склонение, селектор Next_Timed_Task_Today, расчёт целевого множества pending) и хранилище с round-trip-инвариантами. UI-часть (`TaskDetailView`, `NotificationSettingsView`) тестируется примерами и через ViewInspector — для неё свойства не пишем, а в `Testing Strategy` отмечаем как пример-/snapshot-тесты.

### Property 1: TaskItem JSON round-trip

*For any* валидный `TaskItem`, последовательное `JSONEncoder.encode → JSONDecoder.decode` возвращает структуру, эквивалентную исходной (включая поле `dueHasTime`).

**Validates: Requirements 1.2, 10.4**

### Property 2: Backward-compatible decode без `dueHasTime`

*For any* валидный `TaskItem`, после `encode` и удаления ключа `dueHasTime` из JSON, `decode` восстанавливает `TaskItem` с теми же полями и `dueHasTime == false`.

**Validates: Requirements 1.3, 10.1**

### Property 3: Инвариант `dueDate == nil ⇒ dueHasTime == false`

*For any* `TaskItem`, полученный через `init`, `decode(from:)`, `setDueDate`, `clearDueDate` или `applyAssistantActions`, если итоговый `dueDate == nil`, то `dueHasTime == false`.

**Validates: Requirements 1.4, 1.5, 1.8**

### Property 4: setDueDate(hour, minute) сохраняет компоненты

*For any* пары `(hour, minute)` с `hour ∈ 0..23` и `minute ∈ 0..59` и любой задачи `TaskItem` с непустой `dueDate`, после установки времени поле `dueDate` имеет ровно те `hour`/`minute` в локальном календаре, секунды и наносекунды равны нулю, `dueHasTime == true`.

**Validates: Requirements 1.6**

### Property 5: clearTime нормализует к началу дня

*For any* `TaskItem` c `dueDate != nil` и любым `dueHasTime`, после `clearTime` поле `dueDate` равно `Calendar.current.startOfDay(for: original.dueDate!)`, `dueHasTime == false`, и календарная дата в локальной таймзоне не меняется.

**Validates: Requirements 1.7, 2.6**

### Property 6: nextRoundedQuarterHour строго в будущем и кратен 15 минутам

*For any* момента `now: Date` и любой опциональной даты `base: Date?`, результат `nextRoundedQuarterHour(after: now, base: base)` удовлетворяет одновременно: (а) строго больше `now`; (б) минуты ∈ {0, 15, 30, 45}; (в) секунды и наносекунды равны нулю; (г) разница с `now` строго меньше 15 минут (то есть это ближайший такой момент).

**Validates: Requirements 2.4**

### Property 7: TaskStore-уровневый round-trip

*For any* валидной задачи, после `addTask`/`updateTask` в `TaskStore` и последующей загрузки той же задачи по `id`, значения `title`, `notes`, `dueDate`, `dueHasTime`, `isImportant`, `isInMyDay`, `isCompleted` совпадают с тем, что было сохранено.

**Validates: Requirements 2.7**

### Property 8: formatDue согласован с DateFormatter

*For any* `Date` и `Bool hasTime`, результат `formatDue(date:hasTime:locale:timeZone:)` равен `DateFormatter` с `dateStyle == .short` и `timeStyle == (hasTime ? .short : .none)` для тех же `locale` и `timeZone`.

**Validates: Requirements 3.1, 3.2**

### Property 9: parseAssistantDueDate round-trip для двух форматов

*For any* пары `(date, hasTime)`, где `date` имеет нулевые секунды и наносекунды, последовательное «сериализовать в `yyyy-MM-dd` (если `hasTime == false`) или `yyyy-MM-dd'T'HH:mm` (если `hasTime == true`) → `parseAssistantDueDate`» возвращает `(date, hasTime, true)` в текущей локальной таймзоне.

**Validates: Requirements 4.1, 4.2, 4.3**

### Property 10: Невалидный `dueDate` не модифицирует задачу и не прерывает батч

*For any* списка `AssistantAction` и любой строки `dueDate`, не соответствующей ни `yyyy-MM-dd`, ни `yyyy-MM-dd'T'HH:mm`, ни `null`/отсутствию ключа, после `applyAssistantActions` целевая задача не изменяет `dueDate` и `dueHasTime`, `lastErrorMessage != nil`, и все остальные действия батча (включая последующие после ошибочного) применяются.

**Validates: Requirements 4.6**

### Property 11: synchronize детерминирует целевое множество pending

*For any* списка задач `tasks`, любых `NotificationSettings` и любого состояния авторизации `authState`, после `NotificationScheduler.synchronize(with: tasks, settings: settings)` множество pending notification requests равно `target(tasks, settings, authState)`, где `target` определена так:
- если `authState ∉ {.authorized, .provisional}` → `∅`;
- иначе содержит ровно один `morning-digest` тогда и только тогда, когда `morningDigestEnabled == true` и активных-сегодня задач больше нуля, и его trigger.dateComponents совпадают с `morningTime`;
- содержит `task-reminder.<task.id>` для каждого `task` с `!isCompleted && dueHasTime && dueDate != nil && dueDate − leadTime > now`, у которого fireDate-компоненты совпадают с `dueDate − leadTime`.
Дополнительно: повторный вызов `synchronize` с теми же аргументами не меняет состояние (идемпотентность).

**Validates: Requirements 5.6, 5.8, 6.2, 6.3, 6.7, 6.8, 7.3, 7.4, 7.6, 7.7, 7.8, 7.9, 7.10, 7.11, 7.12**

### Property 12: лимит 64 pending — упорядочивание и обрезание

*For any* списка задач (потенциально >64 кандидатов на task-reminder) и любых `NotificationSettings` с `taskRemindersEnabled == true`, после `synchronize` общее число pending ≤ 64, и набор оставленных task-reminder совпадает с первыми `min(N, 64 − reservedForMorning)` элементами кандидатов, отсортированных по возрастанию `dueDate`.

**Validates: Requirements 7.13**

### Property 13: russianTaskWord по русским правилам

*For any* `n: Int` в диапазоне `0..1000`, `russianTaskWord(for: n)` равен:
- `"задач"`, если `n % 100 ∈ 11..14`;
- иначе `"задача"`, если `n % 10 == 1`;
- иначе `"задачи"`, если `n % 10 ∈ 2..4`;
- иначе `"задач"`.

**Validates: Requirements 6.4**

### Property 14: morning notification body содержит правильное содержимое

*For any* непустого списка активных-сегодня задач, `morningBody(activeToday:)` содержит подстроку с `title` ожидаемой ближайшей задачи; если есть Next_Timed_Task_Today, дополнительно содержит подстроку «в HH:mm», где `HH:mm` — `dueDate` ближайшей задачи в локальной таймзоне в 24-часовом формате с ведущими нулями.

**Validates: Requirements 6.5, 6.6**

### Property 15: task reminder body содержит leadTime и время

*For any* `Timed_Task` с `dueDate` и любого `leadMinutes ∈ {5, 15, 30, 60}`, `taskReminderBody(due:leadMinutes:)` содержит подстроку «`Через <leadMinutes> мин`» и подстроку «`в HH:mm`», где `HH:mm` соответствует `dueDate` в локальной таймзоне.

**Validates: Requirements 7.5**

### Property 16: Next_Timed_Task_Today selection алгоритм

*For any* списка `TaskItem` и любого момента `now`, выбранная Next_Timed_Task_Today является элементом множества `{ task | !task.isCompleted && task.dueHasTime && task.dueDate != nil && Calendar.current.isDate(task.dueDate!, inSameDayAs: now) && task.dueDate! >= now }`, и выбирается с минимальным `dueDate`; при равенстве `dueDate` — с лексикографически наименьшим `id.uuidString`. Если множество пустое, выбор отсутствует. Результат не зависит от порядка элементов на входе.

**Validates: Requirements 9.2, 9.3, 9.5**

### Property 17: snapshot.nextTimedTitle обрезается до 80 символов

*For any* `TaskItem`, выбранного как Next_Timed_Task_Today с заголовком `title`, после построения `TodayWidgetSnapshot`: `snapshot.nextTimedTitle!.count == min(title.count, 80)`, `snapshot.nextTimedTitle!` равен `String(title.prefix(80))` (без многоточия), и `snapshot.nextTimedDate == task.dueDate`.

**Validates: Requirements 9.4**

### Property 18: TodayWidgetSnapshot декодируется из старого JSON

*For any* валидного «старого» JSON `TodayWidgetSnapshot` (без ключей `nextTimedTitle` и `nextTimedDate`) `JSONDecoder.decode` не выбрасывает ошибок и возвращает структуру с `nextTimedTitle == nil` и `nextTimedDate == nil`.

**Validates: Requirements 9.6, 10.2**

### Property 19: формат строки виджета содержит title и HH:mm

*For any* пары `(title: String, date: Date)`, результат `formatWidgetNextLine(title:date:)` содержит подстроку `title` и подстроку «HH:mm» в локальной таймзоне устройства в 24-часовом формате с ведущими нулями.

**Validates: Requirements 9.7**

### Property 20: setLeadTime отвергает значения вне `{5, 15, 30, 60}`

*For any* `Int v ∉ {5, 15, 30, 60}`, вызов `setLeadTime(v)` на `NotificationSettings` возвращает `false` и не изменяет поле `leadTimeMinutes`.

**Validates: Requirements 7.2**

### Property 21: NotificationSettingsStore.load → default при невалидной/отсутствующей записи

*For any* содержимого `UserDefaults` (отсутствие записи, произвольный набор байт, валидный JSON c `leadTimeMinutes ∉ {5, 15, 30, 60}` или `morningTime` вне допустимых диапазонов), `NotificationSettingsStore.load` возвращает `NotificationSettings.default`.

**Validates: Requirements 8.10**

### Property 22: каждая закодированная задача содержит ключ `dueHasTime`

*For any* непустого списка `[TaskItem]`, после `JSONEncoder.encode` JSON содержит ключ `"dueHasTime"` ровно `tasks.count` раз (по одному вхождению на задачу).

**Validates: Requirements 10.3**

### Property 23: TaskStorage.loadTasks бросает ошибку при невалидных Data

*For any* непустого набора байт, не являющегося валидным JSON-представлением `[TaskItem]` (по типам полей), `TaskStorage.loadTasks` для файла, содержащего эти байты, выбрасывает ошибку и не возвращает пустой массив.

**Validates: Requirements 10.5**

## Error Handling

### Уровни ошибок

| Источник | Реакция |
|---|---|
| `JSONEncoder.encode` failure при сохранении задач | `TaskStore.lastErrorMessage = "Could not save the latest changes."`. Существующее поведение, не меняется. |
| `JSONDecoder.decode` failure при загрузке задач | `TaskStore.tasks = []`, `lastErrorMessage = "Could not load saved tasks."`. Существующее поведение. Согласно Property 23 — ошибка при невалидных Data не подменяется молчаливым default. |
| Невалидный `dueDate` от AI | `TaskStore.lastErrorMessage = "AI вернул некорректный формат даты"`. Остальные действия батча применяются. |
| `requestAuthorization` throws | `NotificationScheduler.refreshAuthorizationStatus()` вызывается всё равно (он сам не бросает); `NotificationSettingsView.saveError = error.localizedDescription`. Тумблеры не меняются. |
| `add(_ request:)` throws (например, system rate limit) | Логируется через `os.Logger`, отдельный реминд пропускается, остальные продолжают планироваться. Это не critical-error для пользователя. |
| `UserDefaults.set(_:forKey:)` (по факту никогда не throws на iOS, но `JSONEncoder.encode` на `NotificationSettings` может). При неудаче save — `NotificationSettingsView.saveError`, `settings` в памяти не меняется. |
| `NotificationSettingsStore.load` получает невалидные данные | Возвращает `.default`, не сохраняет до явного действия пользователя (Property 21). |
| `loadTasks` нашёл повреждённый файл | Существующий `try storage.loadTasks()` проброс ошибки → store.init catch → `lastErrorMessage`. |
| Permission `.denied` | `NotificationScheduler.synchronize` отменяет всё и не планирует ничего. UI показывает баннер с кнопкой «Открыть настройки iOS». |
| `UIApplication.openSettingsURLString` open failure | Игнорируется (best-effort). |

### Денежные пути (где возможна потеря состояния)

- В `applyAssistantActions` при невалидном `dueDate` критично: остальные поля действия должны примениться. Реализация: парсинг `dueDate` в начале обработки каждого экшена; при ошибке — устанавливается флаг `hadInvalidDate`, остальные `if let` ветки выполняются, в конце action — `if hadInvalidDate { lastErrorMessage = ... }`.

## Testing Strategy

### Стратегия тестов

| Тип | Пакет | Что покрывает |
|---|---|---|
| Unit-тесты (XCTest) | `TemirlanToDoTests` | Все Property #1-23 (через iterations с `XCTest` + helper) и примеры из EXAMPLE-классификаций |
| Snapshot-тесты схемы | `TemirlanToDoTests` | `AssistantSchema.json` как dictionary-snapshot |
| ViewInspector / smoke | `TemirlanToDoTests` | UI-структура `TaskDetailView`, `NotificationSettingsView`, `TaskRowView`, виджет — опционально (если ViewInspector добавляется как test-зависимость; иначе пропускаем и полагаемся на ручную проверку) |

Целевая стратегия — XCTest без внешних PBT-библиотек. Property-тесты реализуются вручную через цикл с генератором (минимум 100 итераций). Это вписывается в существующий CI (`xcodebuild test`) без новых dependencies.

### Property-based testing: минимальный helper

Файл `TemirlanToDoTests/PBT.swift` (новый):

```swift
import XCTest

enum PBT {
    static let defaultIterations = 100
    private static var rng = SystemRandomNumberGenerator()

    static func forAll<A>(
        _ gen: () -> A,
        iterations: Int = defaultIterations,
        file: StaticString = #file,
        line: UInt = #line,
        _ check: (A) throws -> Void
    ) {
        for i in 0..<iterations {
            let value = gen()
            do {
                try check(value)
            } catch {
                XCTFail("Property failed at iteration \(i) with input: \(value). Error: \(error)", file: file, line: line)
                return
            }
        }
    }
}
```

Этот helper достаточен для большинства property-тестов. Каждый property-тест помечен комментарием в формате `// Feature: task-time-and-notifications, Property N: <название>`. Минимум 100 итераций.

### Конкретные тестовые файлы и кейсы

#### `TaskItemMigrationTests.swift` (новый)

Покрывает Properties 1, 2, 3, 22.

```swift
import XCTest
@testable import TemirlanToDo

final class TaskItemMigrationTests: XCTestCase {
    // Feature: task-time-and-notifications, Property 1: TaskItem JSON round-trip
    func testRoundTrip() {
        PBT.forAll(generateTaskItem) { task in
            let data = try JSONEncoder().encode(task)
            let decoded = try JSONDecoder().decode(TaskItem.self, from: data)
            XCTAssertEqual(decoded, task)
        }
    }

    // Feature: task-time-and-notifications, Property 2: backward-compatible decode without dueHasTime
    func testDecodeWithoutDueHasTimeKey() {
        PBT.forAll(generateTaskItem) { task in
            var dict = try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(task)) as! [String: Any]
            dict.removeValue(forKey: "dueHasTime")
            let data = try JSONSerialization.data(withJSONObject: dict)
            let decoded = try JSONDecoder().decode(TaskItem.self, from: data)
            XCTAssertFalse(decoded.dueHasTime)
            XCTAssertEqual(decoded.id, task.id)
            XCTAssertEqual(decoded.title, task.title)
        }
    }

    // Feature: task-time-and-notifications, Property 3: dueDate == nil implies dueHasTime == false
    func testDueDateNilImpliesNoTime() {
        PBT.forAll({ TaskItem(title: "x", dueDate: nil, dueHasTime: Bool.random()) }) { task in
            XCTAssertFalse(task.dueHasTime)
        }
    }

    // Feature: task-time-and-notifications, Property 22: encoded JSON contains dueHasTime per task
    func testEncodedJsonContainsKeyPerTask() { /* ... */ }
}

// generateTaskItem — генератор случайных TaskItem
```

Генератор `generateTaskItem` живёт в `TemirlanToDoTests/Generators.swift` (новый файл), включает варианты `dueDate == nil`, `dueDate != nil && dueHasTime == false`, `dueDate != nil && dueHasTime == true`.

#### `TaskStoreDueDateTests.swift` (новый)

Покрывает Properties 4, 5, 7, 10.

```swift
final class TaskStoreDueDateTests: XCTestCase {
    // Feature: task-time-and-notifications, Property 4: setDueDate preserves hour/minute, zeroes seconds
    func testSetDueDateZeroesSeconds() { /* ... */ }

    // Feature: task-time-and-notifications, Property 5: clearTime normalizes to startOfDay
    func testClearTimeNormalizesToStartOfDay() { /* ... */ }

    // Feature: task-time-and-notifications, Property 7: store-level round-trip
    func testStoreRoundTrip() {
        PBT.forAll(generateTaskItem) { task in
            let store = TaskStore(storage: .inMemory())
            var t = task; t.id = UUID()
            // create via internal API
            store.tasks.insert(t, at: 0); store.save()
            let reloaded = store.tasks.first(where: { $0.id == t.id })!
            XCTAssertEqual(reloaded, t)
        }
    }

    // Feature: task-time-and-notifications, Property 10: invalid dueDate doesn't mutate, batch continues
    func testApplyAssistantActions_invalidDueDate_doesNotBreakBatch() { /* ... */ }
}
```

#### `AssistantDueDateTests.swift` (новый или дополнение к `AssistantActionsTests.swift`)

Покрывает Property 9.

```swift
// Feature: task-time-and-notifications, Property 9: parseAssistantDueDate round-trip for both formats
func testParseAssistantDueDate_roundTrip() {
    PBT.forAll(generateDateAndHasTime) { (date, hasTime) in
        let str = serializeAssistantDueDate(date, hasTime: hasTime)
        let (parsed, parsedHasTime, ok) = TaskStore.parseAssistantDueDate(str, calendar: .current)
        XCTAssertTrue(ok)
        XCTAssertEqual(parsedHasTime, hasTime)
        XCTAssertEqual(parsed, date)
    }
}
```

Дополнительно — пример `applyAssistantActions(dueDate: nil)` на updateTask чистит `dueDate` (Requirement 4.4).

#### `NotificationSettingsTests.swift` (новый)

Покрывает Properties 20, 21.

```swift
// Feature: task-time-and-notifications, Property 20: setLeadTime rejects invalid values
func testSetLeadTimeRejectsInvalid() {
    PBT.forAll({ Int.random(in: -100...500) }) { v in
        guard !NotificationSettings.allowedLeadTimes.contains(v) else { return }
        var s = NotificationSettings.default
        let original = s.leadTimeMinutes
        let ok = s.setLeadTime(v)
        XCTAssertFalse(ok)
        XCTAssertEqual(s.leadTimeMinutes, original)
    }
}

// Feature: task-time-and-notifications, Property 21: load returns default for invalid persisted data
func testLoadReturnsDefaultForInvalidData() { /* generate random Data */ }
```

#### `NotificationSchedulerTests.swift` (новый)

Покрывает Properties 11, 12, 13, 14, 15, 16.

Использует Fake `NotificationCenterProtocol`:

```swift
final class FakeNotificationCenter: NotificationCenterProtocol {
    var authorizationStatus: UNAuthorizationStatus = .authorized
    private(set) var pending: [UNNotificationRequest] = []

    func getNotificationSettings() async -> UNNotificationSettings {
        // Используем реальный UNNotificationSettings нельзя инициализировать напрямую,
        // поэтому отдаём прокси через приватный init или через NSKeyedArchiver-stub.
        // Решение: меняем сигнатуру протокола, чтобы возвращать
        // только authorizationStatus: UNAuthorizationStatus, не сам UNNotificationSettings.
        fatalError("Use authorizationStatusOnly variant")
    }
    // ...
}
```

> Поскольку `UNNotificationSettings` нельзя инстанцировать в тестах, протокол `NotificationCenterProtocol` фактически возвращает не `UNNotificationSettings`, а `UNAuthorizationStatus` напрямую (узкая абстракция). В реализации над `UNUserNotificationCenter` метод вытаскивает `authorizationStatus` из реального settings. Это упрощает Fake.

```swift
// Финальный протокол
protocol NotificationCenterProtocol: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
}
```

Тесты:

```swift
// Feature: task-time-and-notifications, Property 11: synchronize is idempotent and matches target
func testSynchronizeMatchesTargetAndIsIdempotent() {
    PBT.forAll(generateTasksAndSettingsAndAuthState) { (tasks, settings, authState) in
        let fake = FakeNotificationCenter(authorizationStatus: authState)
        let sched = NotificationScheduler(center: fake, calendar: .current, now: { fixedNow })
        await sched.synchronize(with: tasks, settings: settings)
        let first = Set(fake.pending.map(\.identifier))
        await sched.synchronize(with: tasks, settings: settings)
        let second = Set(fake.pending.map(\.identifier))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, expectedTargetIds(tasks: tasks, settings: settings, authState: authState, now: fixedNow))
    }
}

// Feature: task-time-and-notifications, Property 12: 64 pending limit, dueDate ASC truncation
func testPending64Limit() { /* generate >70 timed tasks, expect ≤ 64 pending and earliest first */ }

// Feature: task-time-and-notifications, Property 13: russianTaskWord
func testRussianTaskWord() {
    PBT.forAll({ Int.random(in: 0...1000) }) { n in
        XCTAssertEqual(NotificationScheduler.russianTaskWord(for: n), referenceWord(n))
    }
}

// Feature: task-time-and-notifications, Property 14: morning body content
// Feature: task-time-and-notifications, Property 15: task reminder body content
// Feature: task-time-and-notifications, Property 16: Next_Timed_Task_Today selection
```

#### `TodayWidgetSnapshotTests.swift` (новый)

Покрывает Properties 17, 18, 19.

```swift
// Feature: task-time-and-notifications, Property 17: nextTimedTitle is prefix(80), nextTimedDate equals dueDate
// Feature: task-time-and-notifications, Property 18: snapshot decodes from JSON without next* keys
// Feature: task-time-and-notifications, Property 19: formatWidgetNextLine contains title and HH:mm
```

#### Дополнения в `TaskStorageTests.swift`

```swift
// Feature: task-time-and-notifications, Property 23: loadTasks throws on invalid data
func testLoadTasksThrowsOnInvalidData() {
    PBT.forAll(generateRandomNonEmptyData) { data in
        let url = ... // tmp file
        try data.write(to: url)
        let storage = TaskStorage(fileURL: url)
        XCTAssertThrowsError(try storage.loadTasks())
    }
}
```

(Случайный мусор в подавляющем большинстве случаев валидным JSON-массивом TaskItem не будет; для исключительных совпадений валидного JSON допустимо принять «либо throws, либо decoded с ожидаемой структурой» как смягчение property.)

#### UI / EXAMPLE-тесты

- `TaskDetailView`: пример-тест на `nextRoundedQuarterHour` (helper) + ручная проверка тумблеров.
- `NotificationSettingsView`: пример-тест на чтение/запись через `NotificationSettingsStore` + ручная проверка UI flow.
- `TaskRowView` форматирование: пример-тесты на `formatDue` (Property 8) + EXAMPLE на отсутствие лейбла при `dueDate == nil`.
- `AssistantSchema.json` — snapshot-тест соответствия ключевых полей (тип `dueDate` принимает строку или null).
- Открытие settings URL — spy-mock UIApplication wrapper.

### Стратегия мокирования `UNUserNotificationCenter`

1. Узкий протокол `NotificationCenterProtocol` (см. выше) — возвращает `UNAuthorizationStatus`, не `UNNotificationSettings`, чтобы Fake не зависел от приватных инициализаторов.
2. `UNUserNotificationCenter` адаптируется через extension `extension UNUserNotificationCenter: NotificationCenterProtocol { … }`.
3. Тестовый Fake реализует протокол, держит in-memory `[UNNotificationRequest]`, поддерживает `removePendingNotificationRequests(withIdentifiers:)`, `add`, `removeAllPendingNotificationRequests` и возвращает заданный `authorizationStatus`. Конкретно `UNNotificationRequest` инстанцируется реальным API (его инициализатор публичный).
4. `NotificationScheduler.init(center:calendar:now:)` принимает зависимость через инъекцию — в production используется `UNUserNotificationCenter.current()`, в тестах — `FakeNotificationCenter`.
5. Для проверки времени срабатывания: `now: () -> Date` — в production `Date.init`, в тестах фиксированный момент.
6. `expectedTargetIds(tasks:settings:authState:now:)` — эталонная функция в test-target, реплицирующая бизнес-правила, для сравнения.

### Что не покрывается автоматическими тестами

- Точное поведение iOS при доставке уведомления (это уже зона `UserNotifications.framework`).
- Реальный 64-лимит и его взаимодействие с системой — проверяется только логика scheduler.
- Точные системные алерты разрешений — manual QA на устройстве.
- Перерисовка SwiftUI при смене локали/таймзоны (Requirement 3.5) — проверяется фактическим запуском на устройстве со сменой системной локали.

### Связь с CI

Существующий `xcodebuild test` подхватит новые тесты автоматически, как только файлы попадут в `TemirlanToDoTests` target. Никаких новых внешних зависимостей не вводится. PBT-helper — единственный новый код, ~25 строк.
