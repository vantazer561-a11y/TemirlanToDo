import XCTest
import UserNotifications
@testable import TemirlanToDo

@MainActor
final class NotificationSchedulerTests: XCTestCase {

    // Фиксированный календарь UTC даёт детерминированные DateComponents, не
    // зависящие от региональных DST-сдвигов CI-машины.
    private var gregorianUTC: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    /// Фиксированный «сейчас»: 2026-05-22 09:00 UTC.
    private var fixedNow: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 22
        comps.hour = 9; comps.minute = 0; comps.second = 0
        return gregorianUTC.date(from: comps)!
    }

    /// Создаёт `TaskItem` с `dueDate` в виде `DateComponents` относительно
    /// `gregorianUTC`. Нет таймзонных сюрпризов и DST.
    private func makeTask(
        id: UUID = UUID(),
        title: String = "task",
        isCompleted: Bool = false,
        dueYear: Int? = nil,
        dueMonth: Int? = nil,
        dueDay: Int? = nil,
        dueHour: Int? = nil,
        dueMinute: Int? = nil,
        dueHasTime: Bool = false,
        isInMyDay: Bool = true,
        createdAt: Date? = nil
    ) -> TaskItem {
        let date: Date?
        if let dueYear, let dueMonth, let dueDay {
            var c = DateComponents()
            c.year = dueYear; c.month = dueMonth; c.day = dueDay
            c.hour = dueHour ?? 0; c.minute = dueMinute ?? 0; c.second = 0
            date = gregorianUTC.date(from: c)
        } else {
            date = nil
        }
        return TaskItem(
            id: id,
            title: title,
            notes: "",
            isCompleted: isCompleted,
            isImportant: false,
            createdAt: createdAt ?? fixedNow.addingTimeInterval(-3600),
            updatedAt: fixedNow,
            dueDate: date,
            dueHasTime: dueHasTime,
            isInMyDay: isInMyDay
        )
    }

    private func makeScheduler(
        center: NotificationCenterProtocol,
        now: @escaping () -> Date
    ) -> NotificationScheduler {
        NotificationScheduler(center: center, calendar: gregorianUTC, now: now)
    }

    // MARK: - Property 13: russianTaskWord

    // Feature: task-time-and-notifications, Property 13: russianTaskWord склоняет «задача» по русским правилам
    // Validates: Requirements 6.4
    //
    // Reference-реализация повторяет правила Req 6.4 в отдельной функции и
    // сравнивается с публичной static-функцией для всех `n ∈ 0..1000`.
    func testRussianTaskWord() {
        func reference(_ n: Int) -> String {
            let abs = Swift.abs(n)
            let mod10 = abs % 10
            let mod100 = abs % 100
            if (11...14).contains(mod100) { return "задач" }
            if mod10 == 1 { return "задача" }
            if (2...4).contains(mod10) { return "задачи" }
            return "задач"
        }
        for n in 0...1000 {
            XCTAssertEqual(
                NotificationScheduler.russianTaskWord(for: n),
                reference(n),
                "Mismatch for n=\(n)"
            )
        }
        // Точечные кейсы из Req 6.4.
        let pairs: [(Int, String)] = [
            (1, "задача"), (2, "задачи"), (5, "задач"),
            (11, "задач"), (21, "задача"), (22, "задачи"),
            (25, "задач"), (101, "задача"), (111, "задач"),
            (112, "задач"), (121, "задача")
        ]
        for (n, expected) in pairs {
            XCTAssertEqual(
                NotificationScheduler.russianTaskWord(for: n),
                expected,
                "Spot case n=\(n)"
            )
        }
    }

    // MARK: - Property 9: denied permission is no-op

    // Feature: task-time-and-notifications, Property 9: при `.denied` планировщик не добавляет ничего
    // Validates: Requirements 5.6, 7.12
    //
    // С `.denied` `synchronize` не должен производить новых `add`-вызовов
    // и должен оставить pending пустым.
    func testDeniedPermissionIsNoOp() async {
        let fake = FakeNotificationCenter()
        fake.authorizationStatus = .denied
        let scheduler = makeScheduler(center: fake, now: { self.fixedNow })

        let tasks = [
            makeTask(
                title: "meeting",
                dueYear: 2026, dueMonth: 5, dueDay: 22,
                dueHour: 12, dueMinute: 0, dueHasTime: true
            )
        ]
        await scheduler.synchronize(with: tasks, settings: .default)

        XCTAssertTrue(fake.pending.isEmpty, "Pending must remain empty under .denied")
        XCTAssertEqual(fake.addCallCount, 0, "No add() calls must happen under .denied")
    }

    // MARK: - Property 11 (morning): single instance

    // Feature: task-time-and-notifications, Property 11a: morning digest — единственный экземпляр
    // Validates: Requirements 6.2
    //
    // После двух последовательных synchronize в pending ровно один запрос с id
    // `morning-digest`, его триггер совпадает с `morningTime`, repeats == true.
    func testMorningDigestSingleInstance() async {
        let fake = FakeNotificationCenter()
        fake.authorizationStatus = .authorized
        let scheduler = makeScheduler(center: fake, now: { self.fixedNow })

        let tasks = [
            makeTask(
                title: "myday-task",
                dueYear: 2026, dueMonth: 5, dueDay: 22,
                isInMyDay: true
            )
        ]

        await scheduler.synchronize(with: tasks, settings: .default)
        await scheduler.synchronize(with: tasks, settings: .default)

        let morningEntries = fake.pending.values.filter { $0.identifier == NotificationScheduler.morningDigestId }
        XCTAssertEqual(morningEntries.count, 1, "Exactly one morning-digest must be pending after two syncs")

        guard let request = morningEntries.first,
              let trigger = request.trigger as? UNCalendarNotificationTrigger else {
            XCTFail("Expected UNCalendarNotificationTrigger for morning digest")
            return
        }
        XCTAssertEqual(trigger.dateComponents.hour, 8)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
        XCTAssertTrue(trigger.repeats, "Morning digest trigger must repeat")
    }

    // MARK: - Property 10: task reminders bijection

    // Feature: task-time-and-notifications, Property 10: task-reminder pending = eligible Timed_Tasks
    // Validates: Requirements 7.3, 7.4
    //
    // Среди 5 задач только 3 валидны для напоминания (timed, не выполнены, в будущем).
    // Для каждой ожидаем отдельный pending с id `task-reminder.<UUID>`.
    func testTaskRemindersBijection() async {
        let fake = FakeNotificationCenter()
        fake.authorizationStatus = .authorized
        let scheduler = makeScheduler(center: fake, now: { self.fixedNow })

        // 3 timed-задачи в будущем (с зазором > leadTime по умолчанию = 15 мин).
        let t1 = makeTask(
            title: "t1",
            dueYear: 2026, dueMonth: 5, dueDay: 22,
            dueHour: 12, dueMinute: 0, dueHasTime: true
        )
        let t2 = makeTask(
            title: "t2",
            dueYear: 2026, dueMonth: 5, dueDay: 22,
            dueHour: 14, dueMinute: 30, dueHasTime: true
        )
        let t3 = makeTask(
            title: "t3",
            dueYear: 2026, dueMonth: 5, dueDay: 23,
            dueHour: 9, dueMinute: 0, dueHasTime: true
        )
        // Выполненная — не должна планироваться.
        let tDone = makeTask(
            title: "tDone",
            isCompleted: true,
            dueYear: 2026, dueMonth: 5, dueDay: 22,
            dueHour: 18, dueMinute: 0, dueHasTime: true
        )
        // Без времени — не должна планироваться.
        let tNoTime = makeTask(
            title: "tNoTime",
            dueYear: 2026, dueMonth: 5, dueDay: 22,
            dueHasTime: false
        )

        let allTasks = [t1, t2, t3, tDone, tNoTime]
        await scheduler.synchronize(with: allTasks, settings: .default)

        let reminderIds = Set(
            fake.pending.values
                .map(\.identifier)
                .filter { $0.hasPrefix(NotificationScheduler.taskReminderPrefix) }
        )
        let expected = Set([t1, t2, t3].map { NotificationScheduler.taskReminderId(for: $0.id) })
        XCTAssertEqual(reminderIds, expected, "Reminder set must match eligible tasks bijection")

        for id in reminderIds {
            XCTAssertTrue(
                id.hasPrefix("task-reminder."),
                "Reminder id must start with task-reminder. — got \(id)"
            )
        }
    }

    // MARK: - Property 12: 64 pending limit

    // Feature: task-time-and-notifications, Property 12: при > 64 кандидатов планируем самые ранние
    // Validates: Requirements 7.13
    //
    // Генерируем 100 timed-задач с разными `dueDate`. После synchronize общее
    // число pending ≤ 64 (включая morning-digest), оставленные — самые ранние.
    func testPending64LimitTruncatesByDueDate() async {
        let fake = FakeNotificationCenter()
        fake.authorizationStatus = .authorized
        let scheduler = makeScheduler(center: fake, now: { self.fixedNow })

        var tasks: [TaskItem] = []
        // 100 задач с интервалом 1 час, начиная с +1 час от fixedNow.
        for i in 0..<100 {
            let due = self.fixedNow.addingTimeInterval(Double(i + 1) * 3600)
            let comps = gregorianUTC.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: due
            )
            tasks.append(
                makeTask(
                    id: UUID(),
                    title: "task-\(i)",
                    dueYear: comps.year, dueMonth: comps.month, dueDay: comps.day,
                    dueHour: comps.hour, dueMinute: comps.minute,
                    dueHasTime: true,
                    isInMyDay: false
                )
            )
        }

        await scheduler.synchronize(with: tasks, settings: .default)

        XCTAssertLessThanOrEqual(
            fake.pending.count,
            NotificationScheduler.pendingRequestLimit,
            "Total pending must respect 64 limit"
        )

        // Часть задач (с dueDate на «сегодня») попадают в MyDay → morning-digest
        // планируется. reservedForMorning=1 даёт allowed=63 для напоминаний.
        let reminders = fake.pending.values
            .filter { $0.identifier.hasPrefix(NotificationScheduler.taskReminderPrefix) }
        XCTAssertEqual(reminders.count, 63, "Should schedule 63 reminders (64 - reserved morning slot)")

        // Проверим, что оставленные — самые ранние по dueDate.
        let scheduledTitles = reminders.compactMap { $0.content.title }.sorted()
        let expectedTitles = (0..<63).map { "task-\($0)" }.sorted()
        XCTAssertEqual(scheduledTitles, expectedTitles, "Should keep the 63 earliest tasks")
    }

    // MARK: - Property 11 (reminders): disabled clears

    // Feature: task-time-and-notifications, Property 11b: taskRemindersEnabled=false снимает все task-reminder
    // Validates: Requirements 7.9
    func testTaskRemindersDisabledClears() async {
        let fake = FakeNotificationCenter()
        fake.authorizationStatus = .authorized
        let scheduler = makeScheduler(center: fake, now: { self.fixedNow })

        let tasks = [
            makeTask(
                title: "t1",
                dueYear: 2026, dueMonth: 5, dueDay: 22,
                dueHour: 12, dueMinute: 0, dueHasTime: true
            ),
            makeTask(
                title: "t2",
                dueYear: 2026, dueMonth: 5, dueDay: 22,
                dueHour: 14, dueMinute: 30, dueHasTime: true
            )
        ]

        // Сначала включено: убедимся, что появляются.
        await scheduler.synchronize(with: tasks, settings: .default)
        let beforeReminders = fake.pending.values
            .filter { $0.identifier.hasPrefix(NotificationScheduler.taskReminderPrefix) }
        XCTAssertEqual(beforeReminders.count, 2, "Two reminders expected before disabling")

        // Теперь выключаем напоминания.
        var disabled = NotificationSettings.default
        disabled.taskRemindersEnabled = false
        await scheduler.synchronize(with: tasks, settings: disabled)

        let afterReminders = fake.pending.values
            .filter { $0.identifier.hasPrefix(NotificationScheduler.taskReminderPrefix) }
        XCTAssertTrue(afterReminders.isEmpty, "All task-reminder.* must be cleared")
    }

    // MARK: - Property 15: taskReminderBody format

    // Feature: task-time-and-notifications, Property 15: тело напоминания содержит «Через X мин» и «в HH:mm»
    // Validates: Requirements 7.5
    func testTaskReminderBodyContainsLeadAndTime() {
        let fake = FakeNotificationCenter()
        let scheduler = makeScheduler(center: fake, now: { self.fixedNow })

        struct Sample { let due: Date; let lead: Int }
        let allowedLead = NotificationSettings.allowedLeadTimes
        let gen: () -> Sample = {
            let lead = allowedLead.randomElement()!
            // Random hour 0..23, minute 0..59.
            var c = DateComponents()
            c.year = 2026; c.month = 5; c.day = 22
            c.hour = Int.random(in: 0...23)
            c.minute = Int.random(in: 0...59)
            c.second = 0
            let due = self.gregorianUTC.date(from: c)!
            return Sample(due: due, lead: lead)
        }

        PBT.forAll(gen, iterations: 50) { sample in
            let body = scheduler.taskReminderBody(due: sample.due, leadMinutes: sample.lead)
            XCTAssertTrue(
                body.contains("Через \(sample.lead) мин"),
                "Body must contain 'Через \(sample.lead) мин', got: \(body)"
            )
            // Проверяем подстроку формата HH:mm: совпадает с DateFormatter HH:mm в UTC.
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            formatter.timeZone = self.gregorianUTC.timeZone
            let expectedTime = formatter.string(from: sample.due)
            XCTAssertTrue(
                body.contains("в \(expectedTime)"),
                "Body must contain 'в \(expectedTime)', got: \(body)"
            )
        }
    }

    // MARK: - Property 14: morningBody format

    // Feature: task-time-and-notifications, Property 14: morning body содержит title и HH:mm для timed-задачи
    // Validates: Requirements 6.5
    func testMorningBodyContainsTitleAndTime() {
        let fake = FakeNotificationCenter()
        let scheduler = makeScheduler(center: fake, now: { self.fixedNow })

        let task = makeTask(
            title: "Митинг с командой",
            dueYear: 2026, dueMonth: 5, dueDay: 22,
            dueHour: 14, dueMinute: 30, dueHasTime: true,
            isInMyDay: true
        )
        let body = scheduler.morningBody(activeToday: [task])
        XCTAssertTrue(body.contains("Митинг с командой"), "Body must contain task.title, got: \(body)")
        XCTAssertTrue(body.contains("в 14:30"), "Body must contain 'в HH:mm', got: \(body)")
    }
}
