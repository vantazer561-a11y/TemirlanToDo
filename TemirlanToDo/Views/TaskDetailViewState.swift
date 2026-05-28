import Foundation

/// Начальное состояние тумблеров `Due date` / `Add time` в `TaskDetailView`.
/// _Requirements: 2.8, 2.9_
struct TaskDetailInitialState: Equatable {
    var hasDueDate: Bool
    var hasDueTime: Bool
}

/// Возвращает начальное состояние тумблеров для задачи.
/// `hasDueDate` отражает наличие `dueDate`, `hasDueTime` — флаг `dueHasTime`.
/// _Requirements: 2.8, 2.9_
func makeInitialDetailState(_ task: TaskItem) -> TaskDetailInitialState {
    TaskDetailInitialState(
        hasDueDate: task.dueDate != nil,
        hasDueTime: task.dueHasTime
    )
}

/// Возвращает строго будущий момент с минутами кратно 15 и нулевыми секундами/наносекундами.
///
/// Используется при включении тумблера `Add time` у задачи с уже заданной датой.
/// Поведение:
/// - Если `base != nil` и `base` приходится на тот же локальный день, что `now`,
///   округление происходит относительно `now`.
/// - Если `base` находится в другой день — округление от `startOfDay(of: base)`.
/// - Если `base == nil` — округление от `now`.
/// - Найденный момент — СТРОГО следующий 15-минутный шаг (для 14:00 → 14:15;
///   для 14:15 → 14:30 и т.д.). Это обеспечивает строгий порядок «больше now»
///   даже когда минуты `now` уже кратны 15 (см. инвариант Property 6).
/// - Если ближайший момент пересекает полночь, календарная дата сдвигается на
///   следующий локальный день (например, `now` = 23:50 → результат = 00:00 след. дня).
///
/// _Requirements: 2.4, 2.8, 2.9_
func nextRoundedQuarterHour(
    after now: Date,
    base: Date?,
    calendar: Calendar = .current
) -> Date {
    let referenceForRounding: Date
    if let base, calendar.isDate(base, inSameDayAs: now) {
        referenceForRounding = now
    } else if let base {
        // Округляем от начала локального дня base, чтобы дата осталась "тот же другой день".
        referenceForRounding = calendar.startOfDay(for: base)
    } else {
        referenceForRounding = now
    }

    var components = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second],
        from: referenceForRounding
    )
    let minute = components.minute ?? 0
    // Найти СТРОГО следующий 15-минутный шаг.
    let nextMinute = ((minute / 15) + 1) * 15
    components.second = 0
    components.minute = nextMinute % 60
    if nextMinute >= 60 {
        components.hour = (components.hour ?? 0) + 1
    }
    if (components.hour ?? 0) >= 24 {
        components.hour = 0
        // Перейти на следующий локальный день.
        let dayStart = calendar.startOfDay(for: referenceForRounding)
        if let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) {
            let nextDayComponents = calendar.dateComponents(
                [.year, .month, .day],
                from: nextDay
            )
            components.year = nextDayComponents.year
            components.month = nextDayComponents.month
            components.day = nextDayComponents.day
        }
    }
    return calendar.date(from: components) ?? referenceForRounding
}
