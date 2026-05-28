import Foundation

/// Время суток в локальной таймзоне устройства, без даты. Часы и минуты
/// валидируются в инициализаторе (clamping в допустимый диапазон).
/// _Requirements: 6.1, 8.10_
public struct TimeOfDay: Codable, Equatable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }
}

/// Пользовательские настройки уведомлений: утренний дайджест, тайм-лид
/// напоминаний и связанные тумблеры. Сериализуются JSON-encoder'ом в
/// `UserDefaults` суиты App Group (см. `NotificationSettingsStore`).
/// _Requirements: 6.1, 7.1, 7.2, 8.10_
public struct NotificationSettings: Codable, Equatable {
    public static let allowedLeadTimes: [Int] = [5, 15, 30, 60]

    public var morningDigestEnabled: Bool
    public var morningTime: TimeOfDay
    public var taskRemindersEnabled: Bool
    public var leadTimeMinutes: Int

    public init(
        morningDigestEnabled: Bool,
        morningTime: TimeOfDay,
        taskRemindersEnabled: Bool,
        leadTimeMinutes: Int
    ) {
        self.morningDigestEnabled = morningDigestEnabled
        self.morningTime = morningTime
        self.taskRemindersEnabled = taskRemindersEnabled
        // Если кто-то снаружи передал значение вне множества допустимых —
        // приводим к дефолтному 15. Источник правды — `setLeadTime(_:)`.
        self.leadTimeMinutes = NotificationSettings.allowedLeadTimes.contains(leadTimeMinutes)
            ? leadTimeMinutes
            : 15
    }

    /// Дефолтные настройки: утренний дайджест включён в 08:00,
    /// напоминания включены, lead-time 15 мин. _Requirements: 8.10_
    public static let `default` = NotificationSettings(
        morningDigestEnabled: true,
        morningTime: TimeOfDay(hour: 8, minute: 0),
        taskRemindersEnabled: true,
        leadTimeMinutes: 15
    )

    /// Устанавливает `leadTimeMinutes`, отвергая значения вне множества
    /// `{5, 15, 30, 60}`. Возвращает `true`, если значение принято.
    /// _Requirements: 7.2_
    @discardableResult
    public mutating func setLeadTime(_ value: Int) -> Bool {
        guard NotificationSettings.allowedLeadTimes.contains(value) else { return false }
        leadTimeMinutes = value
        return true
    }

    /// Проверяет диапазоны полей. Используется загрузчиком стора, чтобы
    /// отклонять повреждённые/несовместимые JSON и откатываться к дефолту.
    /// _Requirements: 8.10_
    public static func isValid(_ s: NotificationSettings) -> Bool {
        (0...23).contains(s.morningTime.hour) &&
        (0...59).contains(s.morningTime.minute) &&
        NotificationSettings.allowedLeadTimes.contains(s.leadTimeMinutes)
    }
}
