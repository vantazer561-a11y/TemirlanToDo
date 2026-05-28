import XCTest
@testable import TemirlanToDo

final class TaskStoreSnapshotTests: XCTestCase {

    /// Стабильный календарь для property-тестов: фиксированная UTC-таймзона.
    private func gregorianUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// Reference-реализация: повторяет правила `TaskStore.nextTimedTaskToday`,
    /// чтобы property-тест мог независимо найти ожидаемого кандидата.
    private func referenceNextTimedTaskToday(
        in tasks: [TaskItem],
        now: Date,
        calendar: Calendar
    ) -> TaskItem? {
        let candidates = tasks.filter { task in
            guard !task.isCompleted else { return false }
            guard task.dueHasTime else { return false }
            guard let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: now) && due >= now
        }
        guard !candidates.isEmpty else { return nil }
        return candidates.min { lhs, rhs in
            if lhs.dueDate! != rhs.dueDate! { return lhs.dueDate! < rhs.dueDate! }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Генерирует задачу, чья `dueDate` попадает на тот же UTC-день, что и `now`.
    /// Часы и минуты — случайные (включая моменты до и после `now`). Также
    /// случайно тасуем `dueHasTime`, `isCompleted` и `dueDate == nil` варианты,
    /// чтобы покрыть все ветки фильтра.
    private func makeTask(now: Date, calendar: Calendar) -> TaskItem {
        let variant = Int.random(in: 0...4)
        switch variant {
        case 0:
            // dueDate == nil
            return TaskItem(title: "n", dueDate: nil, dueHasTime: false)
        case 1:
            // dueDate сегодня, hasTime == false
            let dayStart = calendar.startOfDay(for: now)
            return TaskItem(title: "d", dueDate: dayStart, dueHasTime: false)
        case 2:
            // dueDate сегодня, hasTime == true, isCompleted == true
            let dayStart = calendar.startOfDay(for: now)
            let due = dayStart.addingTimeInterval(TimeInterval(Int.random(in: 0..<86_400)))
            return TaskItem(title: "c", isCompleted: true, dueDate: due, dueHasTime: true)
        case 3:
            // dueDate другой день, hasTime == true
            let other = calendar.date(byAdding: .day, value: Int.random(in: 1...10), to: now)!
            return TaskItem(title: "o", dueDate: other, dueHasTime: true)
        default:
            // dueDate сегодня, hasTime == true, активная — кандидат.
            let dayStart = calendar.startOfDay(for: now)
            let secondsInDay = TimeInterval(Int.random(in: 0..<86_400))
            let due = dayStart.addingTimeInterval(secondsInDay)
            return TaskItem(title: "T", dueDate: due, dueHasTime: true)
        }
    }

    // MARK: - Property 16

    // Feature: task-time-and-notifications, Property 16: Next_Timed_Task_Today selection
    // Validates: Requirements 9.2, 9.3, 9.5
    //
    // Для случайного `[TaskItem]` функция возвращает элемент из правильного множества
    // с минимальным `dueDate`; при равенстве — с лексикографически наименьшим
    // `id.uuidString`. Перемешивание входа не меняет результат.
    func testNextTimedTaskTodayDeterministic() {
        let calendar = gregorianUTC()
        let baseNow = Date(timeIntervalSince1970: 1_800_000_000) // фиксированный момент
        // Чтобы получить также случаи равных dueDate, иногда добавляем дубликат.
        struct Input { let tasks: [TaskItem]; let now: Date }
        let gen: () -> Input = {
            let count = Int.random(in: 0...8)
            var arr = (0..<count).map { _ in self.makeTask(now: baseNow, calendar: calendar) }
            // С вероятностью ~30% вставим клон последней задачи с другим id (одинаковый dueDate).
            if let last = arr.last, Int.random(in: 0...9) < 3 {
                let clone = TaskItem(
                    id: UUID(),
                    title: last.title,
                    notes: last.notes,
                    isCompleted: last.isCompleted,
                    isImportant: last.isImportant,
                    createdAt: last.createdAt,
                    updatedAt: last.updatedAt,
                    dueDate: last.dueDate,
                    dueHasTime: last.dueHasTime,
                    isInMyDay: last.isInMyDay
                )
                arr.append(clone)
            }
            return Input(tasks: arr, now: baseNow)
        }

        PBT.forAll(gen) { input in
            let actual = TaskStore.nextTimedTaskToday(in: input.tasks, now: input.now, calendar: calendar)
            let expected = self.referenceNextTimedTaskToday(in: input.tasks, now: input.now, calendar: calendar)
            XCTAssertEqual(actual?.id, expected?.id, "Reference and impl must agree")

            // Перемешивание входа не меняет результат.
            let shuffled = input.tasks.shuffled()
            let shuffledResult = TaskStore.nextTimedTaskToday(in: shuffled, now: input.now, calendar: calendar)
            XCTAssertEqual(shuffledResult?.id, actual?.id, "Result must be invariant under shuffle")
        }
    }
}
