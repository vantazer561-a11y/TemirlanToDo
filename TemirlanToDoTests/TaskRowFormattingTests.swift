import XCTest
@testable import TemirlanToDo

final class TaskRowFormattingTests: XCTestCase {

    /// Стабильная таймзона для всех итераций — разные локали интерпретируют
    /// одни и те же `Date` с одинаковой UTC-зоной, чтобы результат не зависел
    /// от настроек CI-машины.
    private let testTimeZone = TimeZone(identifier: "UTC")!

    private func generateRandomDate() -> Date {
        // Диапазон 2000–2099, целые секунды — без значимых наносекунд.
        Date(timeIntervalSince1970: TimeInterval(Int.random(in: 946_684_800...4_102_444_800)))
    }

    /// Ссылочное форматирование через прямой `DateFormatter` с теми же параметрами.
    private func referenceFormat(
        date: Date,
        hasTime: Bool,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .short
        formatter.timeStyle = hasTime ? .short : .none
        return formatter.string(from: date)
    }

    // Feature: task-time-and-notifications, Property 8: formatDue согласован с DateFormatter
    // Validates: Requirements 3.1, 3.2
    //
    // Для случайной `Date` и случайного `hasTime` результат `formattedDue` должен
    // совпадать с прямым обращением к `DateFormatter` с теми же `locale`/`timeZone`/
    // `dateStyle: .short`/`timeStyle: hasTime ? .short : .none`. Тест прогоняется
    // на двух локалях: `ru_RU` (24-часовой формат, дата `dd.MM.yy`) и `en_US`
    // (12-часовой формат AM/PM, дата `M/d/yy`).
    func testFormattedDueMatchesDateFormatter() {
        let locales = [Locale(identifier: "ru_RU"), Locale(identifier: "en_US")]

        struct Sample { let date: Date; let hasTime: Bool; let locale: Locale }
        let gen: () -> Sample = {
            Sample(
                date: self.generateRandomDate(),
                hasTime: Bool.random(),
                locale: locales.randomElement()!
            )
        }

        PBT.forAll(gen) { sample in
            let expected = self.referenceFormat(
                date: sample.date,
                hasTime: sample.hasTime,
                locale: sample.locale,
                timeZone: self.testTimeZone
            )
            let actual = formattedDue(
                date: sample.date,
                hasTime: sample.hasTime,
                locale: sample.locale,
                timeZone: self.testTimeZone
            )
            XCTAssertEqual(
                actual,
                expected,
                "Mismatch for locale=\(sample.locale.identifier), hasTime=\(sample.hasTime), date=\(sample.date)"
            )
        }
    }
}
