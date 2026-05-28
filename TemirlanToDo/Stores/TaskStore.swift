import Combine
import Foundation

public final class TaskStore: ObservableObject {
    @Published public private(set) var tasks: [TaskItem]
    @Published public var lastErrorMessage: String?

    /// Closure, которое вызывается после успешного `save()`. Используется,
    /// чтобы внешний слой (например, `NotificationScheduler`) мог пересинхронизировать
    /// pending-запросы уведомлений. Опционально — отсутствие подписки не меняет
    /// поведение `TaskStore`.
    /// _Requirements: 5.7, 5.8, 6.8, 7.6, 7.9, 7.11_
    public var notifySchedulerNeedsSync: (() -> Void)?

    private let storage: TaskStorage

    public init(storage: TaskStorage = .live()) {
        self.storage = storage
        do {
            self.tasks = try storage.loadTasks()
        } catch {
            self.tasks = []
            self.lastErrorMessage = "Could not load saved tasks."
        }
    }

    @discardableResult
    public func addTask(title: String, list: TaskListKind) -> TaskItem {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return TaskItem(title: "")
        }

        var task = TaskItem(title: trimmedTitle)
        applyDefaults(for: list, to: &task)
        tasks.insert(task, at: 0)
        save()
        return task
    }

    public func updateTask(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return
        }
        var updated = task
        updated.updatedAt = Date()
        tasks[index] = updated
        save()
    }

    public func deleteTask(_ id: TaskItem.ID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    public func toggleCompletion(for id: TaskItem.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        tasks[index].isCompleted.toggle()
        tasks[index].updatedAt = Date()
        save()
    }

    public func toggleImportance(for id: TaskItem.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        tasks[index].isImportant.toggle()
        tasks[index].updatedAt = Date()
        save()
    }

    /// Устанавливает дату-без-времени для задачи. Дата нормализуется к началу
    /// локального дня (`startOfDay`), а флаг `dueHasTime` сбрасывается в `false`.
    /// _Requirements: 1.5, 2.3_
    public func setDueDate(_ date: Date, for id: TaskItem.ID, calendar: Calendar = .current) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        tasks[index].dueDate = calendar.startOfDay(for: date)
        tasks[index].dueHasTime = false
        tasks[index].updatedAt = Date()
        save()
    }

    /// Устанавливает время для задачи с уже заданной датой. Если у задачи `dueDate == nil`,
    /// операция — no-op (инвариант 1.5: время без даты невозможно).
    /// _Requirements: 1.5, 1.6_
    public func setDueTime(hour: Int, minute: Int, for id: TaskItem.ID, calendar: Calendar = .current) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard let existing = tasks[index].dueDate else {
            return
        }
        var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: existing
        )
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.nanosecond = 0
        guard let newDate = calendar.date(from: components) else {
            return
        }
        tasks[index].dueDate = newDate
        tasks[index].dueHasTime = true
        tasks[index].updatedAt = Date()
        save()
    }

    /// Очищает время у задачи, сохраняя календарную дату. Дата нормализуется к началу
    /// локального дня. Если у задачи `dueDate == nil`, операция — no-op.
    /// _Requirements: 1.7, 2.6_
    public func clearDueTime(for id: TaskItem.ID, calendar: Calendar = .current) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard let existing = tasks[index].dueDate else {
            return
        }
        tasks[index].dueDate = calendar.startOfDay(for: existing)
        tasks[index].dueHasTime = false
        tasks[index].updatedAt = Date()
        save()
    }

    /// Полностью убирает дедлайн у задачи: `dueDate = nil`, `dueHasTime = false`.
    /// _Requirements: 1.8, 2.2_
    public func clearDueDate(for id: TaskItem.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        tasks[index].dueDate = nil
        tasks[index].dueHasTime = false
        tasks[index].updatedAt = Date()
        save()
    }

    public func tasks(for list: TaskListKind, calendar: Calendar = .current) -> [TaskItem] {
        tasks
            .filter { list.contains($0, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    public func save() {
        do {
            try storage.saveTasks(tasks)
            saveTodayWidgetSnapshot()
            lastErrorMessage = nil
            // Уведомить слой уведомлений, что задачи изменились — он сам
            // решит, что пересинхронизировать. _Requirements: 6.8, 7.6, 7.9, 7.11_
            notifySchedulerNeedsSync?()
        } catch {
            lastErrorMessage = "Could not save the latest changes."
        }
    }

    public func applyAssistantActions(_ actions: [AssistantAction], calendar: Calendar = .current) {
        var changed = false
        var dueDateValidationError: String?
        for action in actions {
            switch action.type {
            case .createTask:
                guard let title = action.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                    continue
                }
                var task = TaskItem(title: title)
                task.notes = action.notes ?? ""
                task.isImportant = action.isImportant ?? false
                task.isInMyDay = action.isInMyDay ?? false
                task.isCompleted = action.isCompleted ?? false
                if action.dueDate != nil {
                    let parsed = Self.parseAssistantDueDate(action.dueDate, calendar: calendar)
                    if parsed.isValid {
                        task.dueDate = parsed.date
                        task.dueHasTime = parsed.hasTime
                    } else {
                        // Невалидная строка: создаём задачу без даты, но фиксируем ошибку.
                        // _Requirements: 4.6_
                        dueDateValidationError = "AI вернул некорректный формат даты"
                    }
                }
                tasks.insert(task, at: 0)
                changed = true

            case .updateTask:
                guard
                    let idString = action.taskId,
                    let id = UUID(uuidString: idString),
                    let index = tasks.firstIndex(where: { $0.id == id })
                else {
                    continue
                }
                if let title = action.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    tasks[index].title = title
                }
                if let notes = action.notes {
                    tasks[index].notes = notes
                }
                if let isImportant = action.isImportant {
                    tasks[index].isImportant = isImportant
                }
                if let isInMyDay = action.isInMyDay {
                    tasks[index].isInMyDay = isInMyDay
                }
                if let isCompleted = action.isCompleted {
                    tasks[index].isCompleted = isCompleted
                }
                // Семантика dueDate: см. AssistantAction.dueDateProvided.
                // _Requirements: 4.2, 4.3, 4.4, 4.6_
                if action.dueDateProvided {
                    if let raw = action.dueDate {
                        let parsed = Self.parseAssistantDueDate(raw, calendar: calendar)
                        if parsed.isValid {
                            tasks[index].dueDate = parsed.date
                            tasks[index].dueHasTime = parsed.hasTime
                        } else {
                            // Невалидную дату игнорируем, остальные поля уже применены.
                            dueDateValidationError = "AI вернул некорректный формат даты"
                        }
                    } else {
                        tasks[index].dueDate = nil
                        tasks[index].dueHasTime = false
                    }
                }
                tasks[index].updatedAt = Date()
                changed = true

            case .deleteTask:
                guard let idString = action.taskId, let id = UUID(uuidString: idString) else {
                    continue
                }
                let originalCount = tasks.count
                tasks.removeAll { $0.id == id }
                changed = changed || tasks.count != originalCount

            case .messageOnly:
                continue
            }
        }

        if changed {
            save()
        }
        // `save()` сбрасывает `lastErrorMessage`, поэтому ошибку валидации
        // выставляем после успешной записи. Если save не вызывался (нечего менять),
        // ошибка валидации всё равно фиксируется. _Requirements: 4.6_
        if let error = dueDateValidationError {
            lastErrorMessage = error
        }
    }

    private func applyDefaults(for list: TaskListKind, to task: inout TaskItem) {
        switch list {
        case .myDay:
            task.isInMyDay = true
        case .important:
            task.isImportant = true
        case .planned:
            task.dueDate = Date()
        case .tasks:
            break
        }
    }

    /// Парсит строку `dueDate`, переданную AI-ассистентом, в одном из двух форматов:
    /// `yyyy-MM-dd` (date-only) или `yyyy-MM-dd'T'HH:mm` (с локальным временем).
    /// Возвращает кортеж `(date, hasTime, isValid)`:
    /// - `nil` или пустая строка → `(nil, false, true)` (валидно, действие просто
    ///   очищает дату; см. `applyAssistantActions`).
    /// - распаршенная date-time строка → `(parsedDate, true, true)` со сброшенными
    ///   секундами и наносекундами.
    /// - распаршенная date-only строка → `(startOfDay, false, true)`.
    /// - всё остальное → `(nil, false, false)`.
    /// _Requirements: 4.1, 4.2, 4.3_
    internal static func parseAssistantDueDate(
        _ value: String?,
        calendar: Calendar
    ) -> (date: Date?, hasTime: Bool, isValid: Bool) {
        guard let value, !value.isEmpty else {
            return (nil, false, true)
        }

        // `DateFormatter` с `isLenient = false` всё равно нормализует значения
        // вроде month=13 или hour=25 — поэтому вручную валидируем формат и
        // диапазоны компонентов. Это защищает от тихих смещений даты при
        // парсинге заведомо невалидных строк (Requirements 4.6).
        let dateOnlyRegex = #"^(\d{4})-(\d{2})-(\d{2})$"#
        let dateTimeRegex = #"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$"#

        if let match = value.range(of: dateTimeRegex, options: .regularExpression),
           match == value.startIndex..<value.endIndex {
            let parts = value.split(whereSeparator: { "-T:".contains($0) })
            guard parts.count == 5,
                  let year = Int(parts[0]),
                  let month = Int(parts[1]),
                  let day = Int(parts[2]),
                  let hour = Int(parts[3]),
                  let minute = Int(parts[4]),
                  (1...12).contains(month),
                  (1...31).contains(day),
                  (0...23).contains(hour),
                  (0...59).contains(minute) else {
                return (nil, false, false)
            }
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute
            components.second = 0
            components.nanosecond = 0
            // `calendar.date(from:)` сам отвергнет, например, 31 февраля,
            // потому что Foundation проверит реальную длину месяца только
            // через round-trip dateComponents. Ниже именно это и делаем.
            guard let date = calendar.date(from: components) else {
                return (nil, false, false)
            }
            let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            guard roundTrip.year == year,
                  roundTrip.month == month,
                  roundTrip.day == day,
                  roundTrip.hour == hour,
                  roundTrip.minute == minute else {
                return (nil, false, false)
            }
            return (date, true, true)
        }

        if let match = value.range(of: dateOnlyRegex, options: .regularExpression),
           match == value.startIndex..<value.endIndex {
            let parts = value.split(separator: "-")
            guard parts.count == 3,
                  let year = Int(parts[0]),
                  let month = Int(parts[1]),
                  let day = Int(parts[2]),
                  (1...12).contains(month),
                  (1...31).contains(day) else {
                return (nil, false, false)
            }
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            guard let date = calendar.date(from: components) else {
                return (nil, false, false)
            }
            let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
            guard roundTrip.year == year,
                  roundTrip.month == month,
                  roundTrip.day == day else {
                return (nil, false, false)
            }
            return (calendar.startOfDay(for: date), false, true)
        }

        return (nil, false, false)
    }

    /// Возвращает ближайшую `Timed_Task` на сегодня для виджета.
    /// Условия отбора: `!isCompleted && dueHasTime && dueDate != nil`,
    /// `dueDate` приходится на тот же локальный день, что и `now`, и `dueDate >= now`.
    /// Сортировка: по возрастанию `dueDate`; при равенстве — по лексикографически
    /// наименьшему `id.uuidString` (детерминизм, см. Requirements 9.3).
    /// _Requirements: 9.2, 9.3, 9.5_
    internal static func nextTimedTaskToday(
        in tasks: [TaskItem],
        now: Date,
        calendar: Calendar
    ) -> TaskItem? {
        tasks
            .filter { !$0.isCompleted && $0.dueHasTime && $0.dueDate != nil }
            .filter { calendar.isDate($0.dueDate!, inSameDayAs: now) && $0.dueDate! >= now }
            .sorted { lhs, rhs in
                if lhs.dueDate! != rhs.dueDate! { return lhs.dueDate! < rhs.dueDate! }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first
    }

    private func saveTodayWidgetSnapshot(now: Date = Date(), calendar: Calendar = .current) {
        let todayTasks = tasks
            .filter { !$0.isCompleted && TaskListKind.myDay.contains($0, calendar: calendar) }
            .prefix(3)
        let allTodayCount = tasks.filter { !$0.isCompleted && TaskListKind.myDay.contains($0, calendar: calendar) }.count
        let next = Self.nextTimedTaskToday(in: tasks, now: now, calendar: calendar)
        let nextTimedTitle = next.map { String($0.title.prefix(80)) }
        let nextTimedDate = next?.dueDate
        TodayWidgetSnapshotStore.save(TodayWidgetSnapshot(
            count: allTodayCount,
            titles: todayTasks.map(\.title),
            nextTimedTitle: nextTimedTitle,
            nextTimedDate: nextTimedDate
        ))
    }
}
