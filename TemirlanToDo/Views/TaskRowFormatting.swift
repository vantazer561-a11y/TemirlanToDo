import Foundation

/// Форматирует `dueDate` задачи для отображения в списке.
///
/// Использует `DateFormatter` со `dateStyle = .short` всегда и `timeStyle = .short`,
/// если у задачи задано время (`hasTime == true`). Локализация и таймзона задаются
/// параметрами, чтобы тесты могли проверять детерминированный вывод (см.
/// `TaskRowFormattingTests`).
///
/// _Requirements: 3.1, 3.2, 3.4_
func formattedDue(
    date: Date,
    hasTime: Bool,
    locale: Locale = .current,
    timeZone: TimeZone = .current
) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateStyle = .short
    formatter.timeStyle = hasTime ? .short : .none
    return formatter.string(from: date)
}
