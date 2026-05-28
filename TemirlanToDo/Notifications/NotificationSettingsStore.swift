import Foundation
import Combine

/// Стор для `NotificationSettings`: пишет в `UserDefaults` суиты App Group
/// (`group.com.temirlan.todo`), с fallback на `UserDefaults.standard`, если
/// App Group по какой-то причине недоступна.
///
/// Контракты:
/// - `save(_:)` сначала пишет в `UserDefaults`, и только потом обновляет
///   `@Published settings` — это даёт подписчикам гарантию, что в момент
///   эмиссии значение уже персистентно (Req 8.8).
/// - `load(...)` при отсутствии записи или невалидном JSON возвращает
///   `.default`, БЕЗ записи в UserDefaults. _Requirements: 8.10_
public final class NotificationSettingsStore: ObservableObject {
    private static let key = "notification_settings"
    public static let appGroupIdentifier = "group.com.temirlan.todo"

    @Published public private(set) var settings: NotificationSettings

    private let defaults: UserDefaults
    private let fallback: UserDefaults

    public init(
        defaults: UserDefaults? = UserDefaults(suiteName: NotificationSettingsStore.appGroupIdentifier),
        fallback: UserDefaults = .standard
    ) {
        let primary = defaults ?? fallback
        self.defaults = primary
        self.fallback = fallback
        self.settings = Self.load(defaults: primary, fallback: fallback)
    }

    @discardableResult
    public func save(_ next: NotificationSettings) -> Bool {
        guard NotificationSettings.isValid(next) else { return false }
        guard let data = try? JSONEncoder().encode(next) else { return false }
        // Сначала персистентность, потом @Published-эмиссия.
        defaults.set(data, forKey: Self.key)
        settings = next
        return true
    }

    @discardableResult
    public func update(_ transform: (inout NotificationSettings) -> Bool) -> Bool {
        var next = settings
        guard transform(&next) else { return false }
        return save(next)
    }

    /// Загружает настройки из основного стора (App Group), при необходимости
    /// — из fallback. При невалидных данных возвращает `.default`.
    /// _Requirements: 8.10_
    static func load(defaults: UserDefaults, fallback: UserDefaults) -> NotificationSettings {
        let data = defaults.data(forKey: key) ?? fallback.data(forKey: key)
        guard
            let data,
            let decoded = try? JSONDecoder().decode(NotificationSettings.self, from: data),
            NotificationSettings.isValid(decoded)
        else {
            return .default
        }
        return decoded
    }
}
