import Foundation
import UserNotifications
import os.log

/// Сервис локальных уведомлений: утренний дайджест + точечные напоминания о задачах с временем.
/// Вся работа идёт через `NotificationCenterProtocol`, что делает планировщик легко тестируемым.
/// Идемпотентен: повторные вызовы `synchronize` с теми же входами дают то же состояние pending-запросов.
/// _Requirements: 5.x, 6.x, 7.x_
@MainActor
public final class NotificationScheduler: ObservableObject {
    public static let pendingRequestLimit = 64
    public static let morningDigestId = "morning-digest"
    public static let taskReminderPrefix = "task-reminder."

    public static func taskReminderId(for taskId: UUID) -> String {
        "\(taskReminderPrefix)\(taskId.uuidString)"
    }

    @Published public private(set) var authorizationState: NotificationAuthorizationStatus = .notDetermined

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
    public func requestAuthorization() async -> NotificationAuthorizationStatus {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("requestAuthorization failed: \(error.localizedDescription, privacy: .public)")
        }
        return await refreshAuthorizationStatus()
    }

    @discardableResult
    public func refreshAuthorizationStatus() async -> NotificationAuthorizationStatus {
        let status = await center.getAuthorizationStatus()
        authorizationState = status
        return status
    }

    /// Главная idempotent-операция: применяет целевое состояние pending-запросов к
    /// заданному списку задач и настройкам.
    /// _Requirements: 5.6, 6.2, 6.7, 7.3, 7.6, 7.11, 7.12_
    public func synchronize(with tasks: [TaskItem], settings: NotificationSettings) async {
        let status = await refreshAuthorizationStatus()
        guard status == .authorized || status == .provisional else {
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
        let pending = await center.pendingNotificationRequests()
        let ourIds = pending
            .map(\.identifier)
            .filter { $0 == Self.morningDigestId || $0.hasPrefix(Self.taskReminderPrefix) }
        if !ourIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ourIds)
        }
    }

    // MARK: - Morning digest

    /// Перепланирование утреннего сводного. Идемпотентно: предыдущий запрос
    /// с тем же id всегда удаляется первым шагом.
    /// _Requirements: 6.2, 6.3, 6.7, 6.8_
    func rescheduleMorningDigest(tasks: [TaskItem], settings: NotificationSettings) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.morningDigestId])
        guard settings.morningDigestEnabled else { return }

        let activeToday = self.activeTasksToday(in: tasks)
        guard !activeToday.isEmpty else {
            // Req 6.3: при нуле активных задач сегодня — не планируем уведомление.
            return
        }

        let content = UNMutableNotificationContent()
        content.title = morningTitle(activeCount: activeToday.count)
        content.body = morningBody(activeToday: activeToday)
        content.sound = .default

        var triggerComponents = DateComponents()
        triggerComponents.hour = settings.morningTime.hour
        triggerComponents.minute = settings.morningTime.minute

        let request = UNNotificationRequest(
            identifier: Self.morningDigestId,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: true)
        )
        do {
            try await center.add(request)
        } catch {
            logger.error("Failed to add morning digest: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Task reminders

    /// Перепланирование точечных напоминаний. Сначала очищаем все наши
    /// `task-reminder.*`, затем планируем новые в порядке возрастания `dueDate`,
    /// уважая лимит iOS в 64 pending-запроса.
    /// _Requirements: 7.3, 7.4, 7.6, 7.8, 7.9, 7.10, 7.11, 7.12, 7.13_
    func rescheduleTaskReminders(tasks: [TaskItem], settings: NotificationSettings) async {
        let pending = await center.pendingNotificationRequests()
        let existingIds = pending.map(\.identifier).filter { $0.hasPrefix(Self.taskReminderPrefix) }
        if !existingIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existingIds)
        }

        guard settings.taskRemindersEnabled else { return }

        let lead = TimeInterval(settings.leadTimeMinutes * 60)
        let nowDate = now()
        let candidates = tasks
            .filter { !$0.isCompleted && $0.dueHasTime && $0.dueDate != nil }
            .filter { $0.dueDate!.timeIntervalSince(nowDate) > lead }
            .sorted { lhs, rhs in
                if lhs.dueDate! != rhs.dueDate! { return lhs.dueDate! < rhs.dueDate! }
                return lhs.id.uuidString < rhs.id.uuidString
            }

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
        do {
            try await center.add(request)
        } catch {
            logger.error("Failed to add task reminder for \(task.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Helpers (internal for tests)

    /// Активные на сегодня задачи: `!isCompleted` и попадают в список My Day,
    /// рассчитанный относительно текущего `now()`.
    /// _Requirements: 6.3_
    func activeTasksToday(in tasks: [TaskItem]) -> [TaskItem] {
        let nowDate = now()
        return tasks.filter { task in
            guard !task.isCompleted else { return false }
            return TaskListKind.myDay.contains(task, calendar: calendar, now: nowDate)
        }
    }

    /// Ближайшая `Timed_Task` сегодня среди активных. Сортировка детерминирована:
    /// `dueDate` по возрастанию, при равенстве — `id.uuidString` лексикографически.
    /// _Requirements: 9.2, 9.3_
    func nextTimedTaskToday(in activeToday: [TaskItem]) -> TaskItem? {
        let nowDate = now()
        return activeToday
            .filter { $0.dueHasTime && $0.dueDate != nil }
            .filter { calendar.isDate($0.dueDate!, inSameDayAs: nowDate) && $0.dueDate! >= nowDate }
            .sorted { lhs, rhs in
                if lhs.dueDate! != rhs.dueDate! { return lhs.dueDate! < rhs.dueDate! }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first
    }

    /// Заголовок утреннего сводного: «Сегодня N <словоформа>».
    /// _Requirements: 6.4_
    func morningTitle(activeCount n: Int) -> String {
        "Сегодня \(n) \(Self.russianTaskWord(for: n))"
    }

    /// Тело утреннего сводного. Если есть Next_Timed_Task_Today — упоминаем
    /// его время; иначе — самая ранняя по `dueDate` активная задача
    /// (с детерминированными тай-брейками); fallback — самая недавно созданная.
    /// _Requirements: 6.5, 6.6_
    func morningBody(activeToday: [TaskItem]) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = calendar.timeZone

        if let next = nextTimedTaskToday(in: activeToday) {
            return "Ближайшая: \(next.title) в \(timeFormatter.string(from: next.dueDate!))"
        }
        // Fallback по правилам Req 6.6: самая ранняя по dueDate, при равенстве —
        // самая недавно созданная, при равенстве — наименьший id.uuidString.
        let withDueDate = activeToday.filter { $0.dueDate != nil }
        if let nearest = withDueDate.sorted(by: { lhs, rhs in
            if lhs.dueDate! != rhs.dueDate! { return lhs.dueDate! < rhs.dueDate! }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }).first {
            return "Ближайшая: \(nearest.title)"
        }
        // Совсем без дат — самая недавно созданная.
        if let mostRecent = activeToday.sorted(by: { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }).first {
            return "Ближайшая: \(mostRecent.title)"
        }
        return ""
    }

    /// Тело точечного напоминания: «Через X мин в HH:mm».
    /// _Requirements: 7.5_
    func taskReminderBody(due: Date, leadMinutes: Int) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = calendar.timeZone
        return "Через \(leadMinutes) мин в \(timeFormatter.string(from: due))"
    }

    /// Русское склонение слова «задача» по числу `n`.
    /// _Requirements: 6.4_
    public static func russianTaskWord(for n: Int) -> String {
        let abs = Swift.abs(n)
        let mod10 = abs % 10
        let mod100 = abs % 100
        if (11...14).contains(mod100) { return "задач" }
        if mod10 == 1 { return "задача" }
        if (2...4).contains(mod10) { return "задачи" }
        return "задач"
    }
}
