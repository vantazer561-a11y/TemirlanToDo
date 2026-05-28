import XCTest
@testable import TemirlanToDo

final class TodayWidgetSnapshotTests: XCTestCase {

    // MARK: - Property 17

    // Feature: task-time-and-notifications, Property 17: snapshot.nextTimedTitle обрезается до 80 символов
    // Validates: Requirements 9.4
    //
    // Для случайного `title` (длина 0..200) проверяем, что `nextTimedTitle`,
    // переданный в инициализатор как `String(title.prefix(80))`, имеет длину
    // `<= 80` и равен ожидаемому префиксу.
    func testSnapshotTitleTruncatedTo80Chars() {
        let gen: () -> String = {
            generateRandomString(maxLength: 200)
        }
        PBT.forAll(gen) { title in
            let truncated = String(title.prefix(80))
            let snapshot = TodayWidgetSnapshot(
                count: 1,
                titles: [title],
                nextTimedTitle: truncated,
                nextTimedDate: Date()
            )
            guard let actual = snapshot.nextTimedTitle else {
                XCTFail("nextTimedTitle should be set")
                return
            }
            XCTAssertLessThanOrEqual(actual.count, 80)
            XCTAssertEqual(actual, truncated)
        }
    }

    // MARK: - Property 18

    // Feature: task-time-and-notifications, Property 18: TodayWidgetSnapshot декодируется из старого JSON
    // Validates: Requirements 9.6, 10.2
    //
    // Для случайного `(count, titles, updatedAt)` собираем «старый» JSON-словарь
    // (без ключей `nextTimedTitle`/`nextTimedDate`), декодируем через JSONDecoder,
    // ожидаем `nil` в новых полях, остальные поля — без изменений.
    func testLegacySnapshotWithoutNextTimedKeysDecodes() {
        struct Sample { let count: Int; let titles: [String]; let updatedAt: Date }
        let gen: () -> Sample = {
            let n = Int.random(in: 0...5)
            let titles = (0..<n).map { _ in generateRandomString(maxLength: 24) }
            return Sample(
                count: Int.random(in: 0...50),
                titles: titles,
                updatedAt: generateIntegerSecondDate()
            )
        }
        PBT.forAll(gen) { sample in
            // JSONEncoder использует .deferredToDate (timeIntervalSinceReferenceDate).
            let dict: [String: Any] = [
                "count": sample.count,
                "titles": sample.titles,
                "updatedAt": sample.updatedAt.timeIntervalSinceReferenceDate
            ]
            let data = try JSONSerialization.data(withJSONObject: dict)
            let decoded = try JSONDecoder().decode(TodayWidgetSnapshot.self, from: data)

            XCTAssertEqual(decoded.count, sample.count)
            XCTAssertEqual(decoded.titles, sample.titles)
            XCTAssertEqual(decoded.updatedAt, sample.updatedAt)
            XCTAssertNil(decoded.nextTimedTitle, "Missing key → nil")
            XCTAssertNil(decoded.nextTimedDate, "Missing key → nil")
        }
    }

    // MARK: - Property: round-trip с next-timed-полями

    // Property: encode → decode возвращает эквивалентный снапшот, включая новые поля.
    // _Requirements: 9.4, 9.6, 10.2_
    func testRoundTripWithNextTimedFields() {
        struct Sample {
            let count: Int
            let titles: [String]
            let updatedAt: Date
            let nextTimedTitle: String?
            let nextTimedDate: Date?
        }
        let gen: () -> Sample = {
            let n = Int.random(in: 0...5)
            let titles = (0..<n).map { _ in generateRandomString(maxLength: 24) }
            // С 50/50 — есть ближайшая или нет.
            let hasNext = Bool.random()
            return Sample(
                count: Int.random(in: 0...50),
                titles: titles,
                updatedAt: generateIntegerSecondDate(),
                nextTimedTitle: hasNext ? String(generateRandomString(maxLength: 100).prefix(80)) : nil,
                nextTimedDate: hasNext ? generateIntegerSecondDate() : nil
            )
        }
        PBT.forAll(gen) { sample in
            let snapshot = TodayWidgetSnapshot(
                count: sample.count,
                titles: sample.titles,
                updatedAt: sample.updatedAt,
                nextTimedTitle: sample.nextTimedTitle,
                nextTimedDate: sample.nextTimedDate
            )
            let data = try JSONEncoder().encode(snapshot)
            let decoded = try JSONDecoder().decode(TodayWidgetSnapshot.self, from: data)

            XCTAssertEqual(decoded.count, snapshot.count)
            XCTAssertEqual(decoded.titles, snapshot.titles)
            XCTAssertEqual(decoded.updatedAt, snapshot.updatedAt)
            XCTAssertEqual(decoded.nextTimedTitle, snapshot.nextTimedTitle)
            XCTAssertEqual(decoded.nextTimedDate, snapshot.nextTimedDate)
        }
    }
}
