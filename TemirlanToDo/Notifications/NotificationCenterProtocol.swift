import Foundation
import UserNotifications

/// Авторизация уведомлений как enum, не зависящий от `UNNotificationSettings`.
///
/// `UNNotificationSettings` в iOS нельзя инстанцировать напрямую (нет публичного
/// инициализатора), поэтому в тестах приходилось бы прибегать к KVC-стабам. Эта
/// обёртка позволяет фейк-центру хранить состояние авторизации обычным значением.
/// _Requirements: тест-инфраструктура_
public enum NotificationAuthorizationStatus: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
}

extension NotificationAuthorizationStatus {
    /// Маппинг из системного `UNAuthorizationStatus`.
    public init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .provisional: self = .provisional
        case .ephemeral: self = .ephemeral
        @unknown default: self = .notDetermined
        }
    }
}

/// Узкий фасад поверх `UNUserNotificationCenter`. Существует ради тестируемости —
/// фейк-центр (`FakeNotificationCenter`) реализует его без доступа к реальному
/// нотификационному стеку iOS.
public protocol NotificationCenterProtocol: AnyObject {
    func getAuthorizationStatus() async -> NotificationAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
}

extension UNUserNotificationCenter: NotificationCenterProtocol {
    public func getAuthorizationStatus() async -> NotificationAuthorizationStatus {
        await withCheckedContinuation { (cont: CheckedContinuation<NotificationAuthorizationStatus, Never>) in
            getNotificationSettings { settings in
                cont.resume(returning: NotificationAuthorizationStatus(settings.authorizationStatus))
            }
        }
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            add(request) { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    public func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { (cont: CheckedContinuation<[UNNotificationRequest], Never>) in
            getPendingNotificationRequests { cont.resume(returning: $0) }
        }
    }
}
