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

    // MARK: - Property 10

    // Feature: task-time-and-notifications, Property 10: невалидный `dueDate` не модифицирует задачу
    // Validates: Requirements 4.6
    //
    // Создаём 2 задачи (TaskA с известными `dueDate, dueHasTime, title`, TaskB пустую).
    // Применяем батч из 3 действий:
    //   1. updateTask(TaskA) с невалидным `dueDate` (один из вариантов)
    //      и НОВЫМ `title` — поля, не связанные с датой, должны примениться.
    //   2. updateTask(TaskB) с валидным `dueDate` — должно примениться полностью.
    //   3. updateTask(TaskA) с явным null `dueDate` — должно очистить дату.
    // Однако шаг 3 уничтожит наблюдаемое состояние от шага 1 — поэтому используем
    // отдельные задачи: A для шагов 1, B для шага 2, C для шага 3.
    func testInvalidDueDateLeavesTaskUnchangedAndApplyOtherFields() {
        let invalids = ["hello", "2026/05/24", "2026-13-01", "2026-05-24T25:00"]
        let calendar = gregorianUTC()

        struct Input {
            let invalidString: String
            let originalDueDate: Date
            let originalHasTime: Bool
            let originalTitle: String
            let newTitle: String
            let validForB: String
        }

        let gen: () -> Input = {
            Input(
                invalidString: invalids.randomElement()!,
                originalDueDate: generateIntegerSecondDate(),
                originalHasTime: Bool.random(),
                originalTitle: generateRandomString(maxLength: 20),
                newTitle: generateRandomString(maxLength: 20),
                validForB: "2027-01-15T09:30"
            )
        }

        PBT.forAll(gen) { input in
            let store = TaskStore(storage: .inMemory())

            // TaskA: с известными полями, по которой проверяем "невалидная дата".
            // Title не должен быть пустым/whitespace-only — иначе addTask вернёт стаб без вставки.
            let safeTitleA = input.originalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "A"
                : input.originalTitle
            var taskA = store.addTask(title: safeTitleA, list: .tasks)
            taskA.dueDate = input.originalDueDate
            taskA.dueHasTime = input.originalHasTime
            store.updateTask(taskA)

            // TaskB: для проверки валидной даты.
            let taskB = store.addTask(title: "B", list: .tasks)

            // TaskC: с известной датой, для проверки очистки через dueDate=null.
            var taskC = store.addTask(title: "C", list: .tasks)
            taskC.dueDate = generateIntegerSecondDate()
            taskC.dueHasTime = true
            store.updateTask(taskC)

            // Сбрасываем lastErrorMessage, чтобы проверить, что батч его выставит.
            store.lastErrorMessage = nil

            // newTitle тоже должен быть непустым после trimming, иначе assistant
            // пропустит обновление title.
            let safeNewTitle = input.newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "newA"
                : input.newTitle

            let actions = [
                AssistantAction(
                    type: .updateTask,
                    taskId: taskA.id.uuidString,
                    title: safeNewTitle,
                    notes: nil,
                    isImportant: nil,
                    isInMyDay: nil,
                    isCompleted: nil,
                    dueDate: input.invalidString,
                    dueDateProvided: true
                ),
                AssistantAction(
                    type: .updateTask,
                    taskId: taskB.id.uuidString,
                    title: nil,
                    notes: nil,
                    isImportant: nil,
                    isInMyDay: nil,
                    isCompleted: nil,
                    dueDate: input.validForB,
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

            // Проверки для TaskA: dueDate / dueHasTime не изменились, title — обновился.
            guard let updatedA = store.tasks.first(where: { $0.id == taskA.id }) else {
                XCTFail("TaskA must remain")
                return
            }
            XCTAssertEqual(updatedA.dueDate, input.originalDueDate, "Invalid dueDate must NOT modify task")
            XCTAssertEqual(updatedA.dueHasTime, input.originalHasTime, "Invalid dueDate must NOT modify dueHasTime")
            // Title в action был задан как safeNewTitle (после trimming он непустой),
            // но TaskStore.applyAssistantActions при обновлении использует trimmed-вариант.
            XCTAssertEqual(updatedA.title,
                           safeNewTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                           "title must apply even with invalid dueDate")

            // lastErrorMessage должен быть выставлен.
            XCTAssertNotNil(store.lastErrorMessage, "Invalid dueDate must set lastErrorMessage")

            // Проверки для TaskB: дата применена.
            guard let updatedB = store.tasks.first(where: { $0.id == taskB.id }) else {
                XCTFail("TaskB must remain")
                return
            }
            XCTAssertNotNil(updatedB.dueDate)
            XCTAssertTrue(updatedB.dueHasTime)

            // Проверки для TaskC: дата очищена.
            guard let updatedC = store.tasks.first(where: { $0.id == taskC.id }) else {
                XCTFail("TaskC must remain")
                return
            }
            XCTAssertNil(updatedC.dueDate)
            XCTAssertFalse(updatedC.dueHasTime)
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
