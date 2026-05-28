import XCTest
@testable import TemirlanToDo

final class AssistantDueDateParseTests: XCTestCase {

    /// Стабильный календарь для property-тестов: фиксированная UTC-таймзона,
    /// чтобы избежать DST-сюрпризов на CI.
    private func gregorianUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// Генерирует случайные `(year, month, day, hour, minute)` в безопасных диапазонах
    /// (месяцы 01..12, дни 01..28 — чтобы не зависеть от длины месяца, часы 00..23,
    /// минуты 00..59). Возвращает компоненты вместе с собранной `Date`.
    private func generateDateComponents(calendar: Calendar) -> (DateComponents, Date) {
        var comps = DateComponents()
        comps.year = Int.random(in: 2000...2099)
        comps.month = Int.random(in: 1...12)
        comps.day = Int.random(in: 1...28)
        comps.hour = Int.random(in: 0...23)
        comps.minute = Int.random(in: 0...59)
        comps.second = 0
        comps.nanosecond = 0
        let date = calendar.date(from: comps)!
        return (comps, date)
    }

    private func zeroPad(_ value: Int, width: Int = 2) -> String {
        var s = String(value)
        while s.count < width { s = "0" + s }
        return s
    }

    // MARK: - Property 9

    // Feature: task-time-and-notifications, Property 9: parseAssistantDueDate round-trip
    // Validates: Requirements 4.1, 4.2, 4.3
    //
    // Для случайной даты с нулевыми секундами/наносекундами и `Bool hasTime`:
    // сериализуем строкой соответствующего формата, парсим, ожидаем
    // `(date, hasTime, isValid: true)`.
    func testParseAssistantDueDateRoundTrip() {
        let calendar = gregorianUTC()
        struct Sample { let comps: DateComponents; let hasTime: Bool }
        let gen: () -> Sample = {
            let (comps, _) = self.generateDateComponents(calendar: calendar)
            return Sample(comps: comps, hasTime: Bool.random())
        }
        PBT.forAll(gen) { sample in
            let y = self.zeroPad(sample.comps.year!, width: 4)
            let m = self.zeroPad(sample.comps.month!)
            let d = self.zeroPad(sample.comps.day!)
            let hh = self.zeroPad(sample.comps.hour!)
            let mm = self.zeroPad(sample.comps.minute!)

            let serialized: String
            let expected: Date
            if sample.hasTime {
                serialized = "\(y)-\(m)-\(d)T\(hh):\(mm)"
                expected = calendar.date(from: sample.comps)!
            } else {
                serialized = "\(y)-\(m)-\(d)"
                var dayComps = sample.comps
                dayComps.hour = 0
                dayComps.minute = 0
                expected = calendar.date(from: dayComps)!
            }

            let result = TaskStore.parseAssistantDueDate(serialized, calendar: calendar)
            XCTAssertTrue(result.isValid, "Round-trip parse must be valid for \(serialized)")
            XCTAssertEqual(result.hasTime, sample.hasTime)
            XCTAssertEqual(result.date, expected, "Parsed date mismatch for \(serialized)")
        }
    }

    // MARK: - Property 10 (table-driven)

    // Feature: task-time-and-notifications, Property 10: невалидный `dueDate` не модифицирует задачу
    // Validates: Requirements 4.6
    //
    // Заменили PBT.forAll на табличный тест: создание `TaskStore` ×100 раз
    // дёргает `WidgetCenter.shared.reloadTimelines` через App Group и зависает
    // на iOS Simulator. Property проверяется тем же набором инвариантов, но
    // на конечном множестве показательных невалидных строк.
    func testInvalidDueDateLeavesTaskUnchangedAndApplyOtherFields() {
        let invalids = ["hello", "2026/05/24", "2026-13-01", "2026-05-24T25:00", ""]
        let calendar = gregorianUTC()

        for invalidString in invalids {
            let store = TaskStore(storage: .inMemory())

            // TaskA: с известными полями, по которой проверяем "невалидная дата".
            let originalDate = Date(timeIntervalSince1970: 1_800_000_000)
            var taskA = store.addTask(title: "A", list: .tasks)
            taskA.dueDate = originalDate
            taskA.dueHasTime = true
            store.updateTask(taskA)

            // TaskB: для проверки валидной даты в том же батче.
            let taskB = store.addTask(title: "B", list: .tasks)

            // TaskC: для проверки очистки через dueDate=null.
            var taskC = store.addTask(title: "C", list: .tasks)
            taskC.dueDate = Date(timeIntervalSince1970: 1_900_000_000)
            taskC.dueHasTime = true
            store.updateTask(taskC)

            store.lastErrorMessage = nil

            let actions = [
                AssistantAction(
                    type: .updateTask,
                    taskId: taskA.id.uuidString,
                    title: "newA",
                    notes: nil,
                    isImportant: nil,
                    isInMyDay: nil,
                    isCompleted: nil,
                    dueDate: invalidString.isEmpty ? nil : invalidString,
                    dueDateProvided: !invalidString.isEmpty
                ),
                AssistantAction(
                    type: .updateTask,
                    taskId: taskB.id.uuidString,
                    title: nil,
                    notes: nil,
                    isImportant: nil,
                    isInMyDay: nil,
                    isCompleted: nil,
                    dueDate: "2027-01-15T09:30",
                    dueDateProvided: true
                ),
                AssistantAction(
                    type: .updateTask,
                    taskId: taskC.id.uuidString,
                    title: nil,
                    notes: nil,
                    isImportant: nil,
                    isInMyDay: nil,
                    isCompleted: nil,
                    dueDate: nil,
                    dueDateProvided: true
                )
            ]

            store.applyAssistantActions(actions, calendar: calendar)

            // TaskA: dueDate / dueHasTime не изменились (для непустой невалидной строки).
            // Если invalidString == "" — это `dueDateProvided == false`, тоже не трогаем.
            guard let updatedA = store.tasks.first(where: { $0.id == taskA.id }) else {
                XCTFail("TaskA must remain (input: \(invalidString))")
                continue
            }
            XCTAssertEqual(updatedA.dueDate, originalDate,
                           "Invalid dueDate must NOT modify task (input: \(invalidString))")
            XCTAssertTrue(updatedA.dueHasTime,
                          "Invalid dueDate must NOT modify dueHasTime (input: \(invalidString))")
            XCTAssertEqual(updatedA.title, "newA",
                           "title must apply even with invalid dueDate (input: \(invalidString))")

            // lastErrorMessage выставляется только для непустой невалидной строки.
            if !invalidString.isEmpty {
                XCTAssertNotNil(store.lastErrorMessage,
                                "Invalid dueDate must set lastErrorMessage (input: \(invalidString))")
            }

            // TaskB: дата применена.
            guard let updatedB = store.tasks.first(where: { $0.id == taskB.id }) else {
                XCTFail("TaskB must remain")
                continue
            }
            XCTAssertNotNil(updatedB.dueDate, "TaskB dueDate must be set (input: \(invalidString))")
            XCTAssertTrue(updatedB.dueHasTime,
                          "TaskB dueHasTime must be true (input: \(invalidString))")

            // TaskC: дата очищена.
            guard let updatedC = store.tasks.first(where: { $0.id == taskC.id }) else {
                XCTFail("TaskC must remain")
                continue
            }
            XCTAssertNil(updatedC.dueDate, "TaskC dueDate must be cleared (input: \(invalidString))")
            XCTAssertFalse(updatedC.dueHasTime,
                           "TaskC dueHasTime must be false (input: \(invalidString))")
        }
    }

    // MARK: - Unit-тест: dueDateProvided

    // Unit-тест: `dueDateProvided` отделяет «не трогать» от «очистить».
    // _Requirements: 4.4_
    func testDueDateProvidedDistinguishesFromNull() throws {
        let calendar = gregorianUTC()

        let store = TaskStore(storage: .inMemory())
        var task = store.addTask(title: "Existing", list: .tasks)
        let originalDate = Date(timeIntervalSince1970: 1_800_000_000)
        task.dueDate = originalDate
        task.dueHasTime = true
        store.updateTask(task)

        // Декодируем JSON БЕЗ ключа dueDate.
        let withoutKeyJSON = """
        {"type":"update_task","taskId":"\(task.id.uuidString)","title":"x"}
        """
        let withoutKey = try JSONDecoder().decode(AssistantAction.self, from: Data(withoutKeyJSON.utf8))
        XCTAssertFalse(withoutKey.dueDateProvided, "Missing key → dueDateProvided == false")
        XCTAssertNil(withoutKey.dueDate)

        // Декодируем JSON с dueDate: null.
        let withNullJSON = """
        {"type":"update_task","taskId":"\(task.id.uuidString)","title":"x","dueDate":null}
        """
        let withNull = try JSONDecoder().decode(AssistantAction.self, from: Data(withNullJSON.utf8))
        XCTAssertTrue(withNull.dueDateProvided, "Explicit key → dueDateProvided == true")
        XCTAssertNil(withNull.dueDate)

        // Применяем «без ключа» — dueDate остаётся.
        store.applyAssistantActions([withoutKey], calendar: calendar)
        let afterFirst = store.tasks.first { $0.id == task.id }
        XCTAssertEqual(afterFirst?.dueDate, originalDate, "Missing key must leave dueDate untouched")
        XCTAssertTrue(afterFirst?.dueHasTime ?? false, "Missing key must leave dueHasTime untouched")
        XCTAssertEqual(afterFirst?.title, "x", "Other fields must apply")

        // Применяем «с null» — dueDate очищается.
        store.applyAssistantActions([withNull], calendar: calendar)
        let afterSecond = store.tasks.first { $0.id == task.id }
        XCTAssertNil(afterSecond?.dueDate, "Explicit null must clear dueDate")
        XCTAssertFalse(afterSecond?.dueHasTime ?? true, "Explicit null must clear dueHasTime")
    }
}
