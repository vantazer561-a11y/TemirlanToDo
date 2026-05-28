import XCTest
@testable import TemirlanToDo

final class TaskItemMigrationTests: XCTestCase {

    // Feature: task-time-and-notifications, Property 1: TaskItem JSON round-trip
    // Validates: Requirements 1.2, 10.4
    //
    // Случайная `TaskItem` после `JSONEncoder().encode → JSONDecoder().decode`
    // равна исходной.
    func testRoundTrip() {
        PBT.forAll(generateTaskItem) { task in
            let data = try JSONEncoder().encode(task)
            let decoded = try JSONDecoder().decode(TaskItem.self, from: data)
            XCTAssertEqual(decoded, task)
        }
    }

    // Feature: task-time-and-notifications, Property 2: Backward-compatible decode без `dueHasTime`
    // Validates: Requirements 1.3, 10.1
    //
    // Сериализуем случайную `TaskItem` в JSON-словарь, удаляем ключ `dueHasTime`,
    // декодируем обратно — задача должна декодироваться без ошибок,
    // `dueHasTime` должен быть `false`, остальные поля (включая `dueDate`
    // без модификации) — без изменений.
    func testDecodeWithoutDueHasTimeKey() {
        PBT.forAll(generateTaskItem) { task in
            let data = try JSONEncoder().encode(task)
            guard
                var dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                XCTFail("Expected JSON object")
                return
            }
            dict.removeValue(forKey: "dueHasTime")
            let strippedData = try JSONSerialization.data(withJSONObject: dict)
            let decoded = try JSONDecoder().decode(TaskItem.self, from: strippedData)

            XCTAssertFalse(decoded.dueHasTime, "Decoder must default missing dueHasTime to false")
            XCTAssertEqual(decoded.id, task.id)
            XCTAssertEqual(decoded.title, task.title)
            XCTAssertEqual(decoded.notes, task.notes)
            XCTAssertEqual(decoded.isCompleted, task.isCompleted)
            XCTAssertEqual(decoded.isImportant, task.isImportant)
            XCTAssertEqual(decoded.createdAt, task.createdAt)
            XCTAssertEqual(decoded.updatedAt, task.updatedAt)
            XCTAssertEqual(decoded.dueDate, task.dueDate)
            XCTAssertEqual(decoded.isInMyDay, task.isInMyDay)
        }
    }

    // Feature: task-time-and-notifications, Property 3: dueDate == nil ⇒ dueHasTime == false
    // Validates: Requirements 1.4, 1.5, 1.8
    //
    // JSON с `"dueDate": null, "dueHasTime": <random Bool>` после декодирования
    // имеет `dueHasTime == false`. Параметризовано через PBT.forAll по
    // `Bool.random()` для исходного значения `dueHasTime`.
    func testDueDateNilForcesDueHasTimeFalse() {
        PBT.forAll({ Bool.random() }) { rawHasTime in
            let id = UUID()
            let createdAt = generateIntegerSecondDate()
            let updatedAt = generateIntegerSecondDate()
            // JSONEncoder использует `.deferredToDate` (timeIntervalSinceReferenceDate
            // как Double) — подставляем такое же представление в ручной JSON.
            let json: [String: Any] = [
                "id": id.uuidString,
                "title": "stripe",
                "notes": "",
                "isCompleted": false,
                "isImportant": false,
                "createdAt": createdAt.timeIntervalSinceReferenceDate,
                "updatedAt": updatedAt.timeIntervalSinceReferenceDate,
                "dueDate": NSNull(),
                "dueHasTime": rawHasTime,
                "isInMyDay": false
            ]
            let data = try JSONSerialization.data(withJSONObject: json)
            let decoded = try JSONDecoder().decode(TaskItem.self, from: data)

            XCTAssertNil(decoded.dueDate)
            XCTAssertFalse(
                decoded.dueHasTime,
                "JSON dueDate=null + dueHasTime=\(rawHasTime) → dueHasTime must be false"
            )
            XCTAssertEqual(decoded.id, id)
        }
    }

    // Feature: task-time-and-notifications, Property 22: каждая закодированная задача содержит ключ `dueHasTime`
    // Validates: Requirements 10.3
    //
    // Для случайного `[TaskItem]` число вхождений ключа `"dueHasTime"` в JSON
    // равно `tasks.count`. Алфавит генератора (`generateRandomString`) не
    // содержит символа `"`, поэтому подстрока `"\"dueHasTime\""` не может
    // встретиться внутри полей `title`/`notes`.
    func testEncodedJsonContainsDueHasTimeKeyPerTask() {
        PBT.forAll({ () -> [TaskItem] in
            let count = Int.random(in: 0...5)
            return (0..<count).map { _ in generateTaskItem() }
        }) { tasks in
            let data = try JSONEncoder().encode(tasks)
            guard let json = String(data: data, encoding: .utf8) else {
                XCTFail("Expected UTF-8 JSON")
                return
            }
            let needle = "\"dueHasTime\""
            var occurrences = 0
            var searchRange = json.startIndex..<json.endIndex
            while let found = json.range(of: needle, range: searchRange) {
                occurrences += 1
                searchRange = found.upperBound..<json.endIndex
            }
            XCTAssertEqual(occurrences, tasks.count)
        }
    }
}
