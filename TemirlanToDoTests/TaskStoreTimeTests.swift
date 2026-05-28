import XCTest
@testable import TemirlanToDo

final class TaskStoreTimeTests: XCTestCase {

    // MARK: - Helpers

    /// Стабильный календарь для property-тестов: фиксированная таймзона избегает
    /// сюрпризов с DST на CI и не зависит от настроек устройства.
    private func gregorianCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func makeFileBackedStorage() -> (TaskStorage, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        return (TaskStorage(fileURL: url), url)
    }

    // MARK: - Property 4

    // Feature: task-time-and-notifications, Property 4: setDueTime сохраняет компоненты времени
    // Validates: Requirements 1.6
    //
    // Для случайной задачи с заданной `dueDate` и случайных `(hour, minute)` после
    // `setDueTime` поле `dueDate` имеет ровно эти `hour`/`minute`, секунды и наносекунды
    // равны нулю, календарная дата (year/month/day) не изменилась, `dueHasTime == true`.
    func testSetDueTimePreservesComponents() {
        let calendar = gregorianCalendar()
        struct Input { let baseDate: Date; let hour: Int; let minute: Int }
        let gen: () -> Input = {
            Input(
                baseDate: generateIntegerSecondDate(),
                hour: Int.random(in: 0...23),
                minute: Int.random(in: 0...59)
            )
        }
        PBT.forAll(gen) { input in
            let store = TaskStore(storage: .inMemory())
            var task = store.addTask(title: "T", list: .tasks)
            task.dueDate = input.baseDate
            task.dueHasTime = false
            store.updateTask(task)

            let originalDay = calendar.dateComponents([.year, .month, .day], from: input.baseDate)

            store.setDueTime(hour: input.hour, minute: input.minute, for: task.id, calendar: calendar)

            guard let updated = store.tasks.first(where: { $0.id == task.id }),
                  let due = updated.dueDate else {
                XCTFail("Task with dueDate expected after setDueTime")
                return
            }
            let parts = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second, .nanosecond],
                from: due
            )
            XCTAssertEqual(parts.year, originalDay.year)
            XCTAssertEqual(parts.month, originalDay.month)
            XCTAssertEqual(parts.day, originalDay.day)
            XCTAssertEqual(parts.hour, input.hour)
            XCTAssertEqual(parts.minute, input.minute)
            XCTAssertEqual(parts.second, 0)
            XCTAssertEqual(parts.nanosecond, 0)
            XCTAssertTrue(updated.dueHasTime)
        }
    }

    // MARK: - Property 5

    // Feature: task-time-and-notifications, Property 5: clearDueTime нормализует к началу дня
    // Validates: Requirements 1.7, 2.6
    //
    // Для случайной задачи с `dueDate != nil` и любым исходным `dueHasTime` после
    // `clearDueTime` календарная дата (year/month/day) не меняется, hour/minute/second/nanosecond == 0,
    // `dueHasTime == false`.
    func testClearDueTimeNormalizesToStartOfDay() {
        let calendar = gregorianCalendar()
        let gen: () -> (Date, Bool) = {
            (generateIntegerSecondDate(), Bool.random())
        }
        PBT.forAll(gen) { (baseDate, hasTime) in
            let store = TaskStore(storage: .inMemory())
            var task = store.addTask(title: "X", list: .tasks)
            task.dueDate = baseDate
            task.dueHasTime = hasTime
            store.updateTask(task)

            let originalDay = calendar.dateComponents([.year, .month, .day], from: baseDate)

            store.clearDueTime(for: task.id, calendar: calendar)

            guard let updated = store.tasks.first(where: { $0.id == task.id }),
                  let due = updated.dueDate else {
                XCTFail("Task should still have dueDate after clearDueTime")
                return
            }
            let parts = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second, .nanosecond],
                from: due
            )
            XCTAssertEqual(parts.year, originalDay.year)
            XCTAssertEqual(parts.month, originalDay.month)
            XCTAssertEqual(parts.day, originalDay.day)
            XCTAssertEqual(parts.hour, 0)
            XCTAssertEqual(parts.minute, 0)
            XCTAssertEqual(parts.second, 0)
            XCTAssertEqual(parts.nanosecond, 0)
            XCTAssertFalse(updated.dueHasTime)
        }
    }

    // MARK: - Property 7

    // Feature: task-time-and-notifications, Property 7: TaskStore round-trip через storage
    // Validates: Requirements 2.7
    //
    // Создаём задачу через `addTask`, фиксируем поля, пересоздаём `TaskStore` поверх
    // того же file-backed `TaskStorage` — задача загружается с теми же значениями.
    func testStoreRoundTrip() {
        PBT.forAll({ generateTaskItem() }) { sample in
            let (storage, url) = self.makeFileBackedStorage()
            defer { try? FileManager.default.removeItem(at: url) }

            let store = TaskStore(storage: storage)
            var added = store.addTask(title: sample.title.isEmpty ? "x" : sample.title, list: .tasks)
            added.notes = sample.notes
            added.isCompleted = sample.isCompleted
            added.isImportant = sample.isImportant
            added.isInMyDay = sample.isInMyDay
            added.dueDate = sample.dueDate
            added.dueHasTime = sample.dueHasTime
            store.updateTask(added)

            let expected = store.tasks
            let reloaded = TaskStore(storage: TaskStorage(fileURL: url))
            XCTAssertEqual(reloaded.tasks, expected)
        }
    }

    // MARK: - Unit test

    // Unit-тест: clearDueDate обнуляет оба поля. _Requirements: 1.8_
    func testClearDueDateZerosBoth() {
        let store = TaskStore(storage: .inMemory())
        var task = store.addTask(title: "Deadline", list: .tasks)
        task.dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        task.dueHasTime = true
        store.updateTask(task)

        store.clearDueDate(for: task.id)

        let updated = store.tasks.first { $0.id == task.id }
        XCTAssertNotNil(updated)
        XCTAssertNil(updated?.dueDate)
        XCTAssertFalse(updated?.dueHasTime ?? true)
    }
}
