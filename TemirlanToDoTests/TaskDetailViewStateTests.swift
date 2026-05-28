import XCTest
@testable import TemirlanToDo

final class TaskDetailViewStateTests: XCTestCase {

    /// Локальный календарь с фиксированной таймзоной для устойчивости PBT-итераций
    /// против DST-сдвигов на CI-машине.
    private func gregorianUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func generateRandomDate(calendar: Calendar) -> Date {
        // 2000-01-01 .. 2099-12-31 в UTC.
        var comps = DateComponents()
        comps.year = Int.random(in: 2000...2099)
        comps.month = Int.random(in: 1...12)
        comps.day = Int.random(in: 1...28)
        comps.hour = Int.random(in: 0...23)
        comps.minute = Int.random(in: 0...59)
        comps.second = Int.random(in: 0...59)
        comps.nanosecond = 0
        return calendar.date(from: comps)!
    }

    // MARK: - Property 6

    // Feature: task-time-and-notifications, Property 6: nextRoundedQuarterHour инварианты
    // Validates: Requirements 2.4
    //
    // Для случайного `now` и `base ∈ {nil, same-day, other-day}`:
    //  (а) результат строго больше «reference точки»;
    //  (б) `minute % 15 == 0`;
    //  (в) `second == 0 && nanosecond == 0`;
    //  (г) разница с reference-точкой не более 15 минут.
    func testNextRoundedQuarterHourInvariants() {
        let calendar = gregorianUTC()

        struct Sample {
            let now: Date
            let base: Date?
            let baseKind: String   // for debugging
        }

        let gen: () -> Sample = {
            let now = self.generateRandomDate(calendar: calendar)
            let kind = Int.random(in: 0...2)
            switch kind {
            case 0:
                return Sample(now: now, base: nil, baseKind: "nil")
            case 1:
                // same-day base — берём начало того же дня и добавляем случайные часы/минуты.
                let dayStart = calendar.startOfDay(for: now)
                let offset = TimeInterval(Int.random(in: 0..<86400))
                return Sample(
                    now: now,
                    base: dayStart.addingTimeInterval(offset),
                    baseKind: "same-day"
                )
            default:
                // other-day base — отстоящий на 1..30 дней (вперёд или назад).
                let direction: Int = Bool.random() ? 1 : -1
                let days = Int.random(in: 1...30) * direction
                let other = calendar.date(byAdding: .day, value: days, to: now)!
                return Sample(now: now, base: other, baseKind: "other-day")
            }
        }

        PBT.forAll(gen) { sample in
            let result = nextRoundedQuarterHour(
                after: sample.now,
                base: sample.base,
                calendar: calendar
            )

            // Reference-точка для строгого сравнения «больше».
            let reference: Date
            if let base = sample.base, calendar.isDate(base, inSameDayAs: sample.now) {
                reference = sample.now
            } else if let base = sample.base {
                reference = calendar.startOfDay(for: base)
            } else {
                reference = sample.now
            }

            // (а) строго больше reference.
            XCTAssertGreaterThan(
                result.timeIntervalSince(reference),
                0,
                "Result must be strictly after reference. base=\(sample.baseKind), now=\(sample.now), result=\(result)"
            )

            let resultComponents = calendar.dateComponents(
                [.minute, .second, .nanosecond],
                from: result
            )

            // (б) минуты кратны 15.
            let minute = resultComponents.minute ?? -1
            XCTAssertTrue(
                minute % 15 == 0 && (0...59).contains(minute),
                "Minute must be 0/15/30/45, got \(minute)"
            )

            // (в) секунды и наносекунды равны нулю.
            XCTAssertEqual(resultComponents.second, 0, "Seconds must be zero")
            XCTAssertEqual(resultComponents.nanosecond ?? 0, 0, "Nanoseconds must be zero")

            // (г) разница не более 15 минут.
            let delta = result.timeIntervalSince(reference)
            XCTAssertLessThanOrEqual(
                delta,
                15 * 60,
                "Result must be within 15 minutes of reference. delta=\(delta)"
            )
        }
    }

    // Корнер-кейс: now = 23:50 → результат на следующий локальный день, 00:00.
    func testNextRoundedQuarterHour2350TransitionsToNextDay() {
        let calendar = gregorianUTC()
        var nowComps = DateComponents()
        nowComps.year = 2026
        nowComps.month = 5
        nowComps.day = 24
        nowComps.hour = 23
        nowComps.minute = 50
        nowComps.second = 30
        let now = calendar.date(from: nowComps)!

        let result = nextRoundedQuarterHour(after: now, base: nil, calendar: calendar)

        let comps = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: result
        )
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 5)
        XCTAssertEqual(comps.day, 25, "Date must roll over to next day")
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
        XCTAssertEqual(comps.second, 0)
        XCTAssertEqual(comps.nanosecond ?? 0, 0)
    }

    // MARK: - Unit: makeInitialDetailState

    // Unit-тест: makeInitialDetailState отражает задачу.
    // _Requirements: 2.8, 2.9_
    func testMakeInitialDetailStateMirrorsTask() {
        // Кейс 1: dueDate = nil, hasTime = false.
        let taskNoDate = TaskItem(title: "no-date", dueDate: nil, dueHasTime: false)
        XCTAssertEqual(
            makeInitialDetailState(taskNoDate),
            TaskDetailInitialState(hasDueDate: false, hasDueTime: false)
        )

        // Кейс 2: dueDate = set, hasTime = false.
        let taskDateOnly = TaskItem(
            title: "date-only",
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            dueHasTime: false
        )
        XCTAssertEqual(
            makeInitialDetailState(taskDateOnly),
            TaskDetailInitialState(hasDueDate: true, hasDueTime: false)
        )

        // Кейс 3: dueDate = set, hasTime = true.
        let taskWithTime = TaskItem(
            title: "with-time",
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            dueHasTime: true
        )
        XCTAssertEqual(
            makeInitialDetailState(taskWithTime),
            TaskDetailInitialState(hasDueDate: true, hasDueTime: true)
        )
    }
}
