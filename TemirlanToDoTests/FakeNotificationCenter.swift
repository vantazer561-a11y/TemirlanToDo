import Foundation
import UserNotifications
@testable import TemirlanToDo

/// In-memory fake поверх `NotificationCenterProtocol` для тестов.
///
/// Хранит `pending` как `[String: UNNotificationRequest]`, поддерживает
/// настраиваемый `authorizationStatus` (через enum-обёртку, без KVC).
/// Счётчики помогают верифицировать частоту обращений в idempotency-тестах.
final class FakeNotificationCenter: NotificationCenterProtocol {
    var authorizationStatus: NotificationAuthorizationStatus = .authorized
    var requestAuthorizationResult: Result<Bool, Error> = .success(true)
    var addError: Error?

    private(set) var pending: [String: UNNotificationRequest] = [:]
    private(set) var addCallCount = 0
    private(set) var requestAuthorizationCallCount = 0
    private(set) var removeCallCount = 0

    func getAuthorizationStatus() async -> NotificationAuthorizationStatus {
        authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationCallCount += 1
        switch requestAuthorizationResult {
        case .success(let granted):
            if granted {
                authorizationStatus = .authorized
            }
            return granted
        case .failure(let err):
            throw err
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        addCallCount += 1
        if let addError {
            throw addError
        }
        pending[request.identifier] = request
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        Array(pending.values)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removeCallCount += 1
        for id in identifiers {
            pending.removeValue(forKey: id)
        }
    }

    func removeAllPendingNotificationRequests() {
        removeCallCount += 1
        pending.removeAll()
    }
}
