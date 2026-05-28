import XCTest
import Combine
@testable import TemirlanToDo

final class NotificationSettingsTests: XCTestCase {

    private var createdSuiteNames: [String] = []

    override func tearDown() {
        super.tearDown()
        // Чистим суиты, созданные в тестах, чтобы данные не утекали между прогонами.
        for name in createdSuiteNames {
            UserDefaults().removePersistentDomain(forName: name)
        }
        createdSuiteNames.removeAll()
    }

    /// Создаёт изолированный `UserDefaults(suiteName:)`, регистрируя имя для tearDown.
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let name = "test-\(UUID().uuidString)"
        createdSuiteNames.append(name)
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    // MARK: - Property 20

    // Feature: task-time-and-notifications, Property 20: setLeadTime отвергает значения вне `{5,15,30,60}`
    // Validates: Requirements 7.2
    //
    // Для случайного `Int v`:
    //  - если `v ∉ {5, 15, 30, 60}` — `setLeadTime` возвращает `false`
    //    и `leadTimeMinutes` не меняется;
    //  - иначе возвращает `true` и значение применяется.
    func testSetLeadTimeRejectsInvalid() {
        PBT.forAll({ Int.random(in: -100...200) }) { v in
            var settings = NotificationSettings.default
            let originalLead = settings.leadTimeMinutes
            let result = settings.setLeadTime(v)
            if NotificationSettings.allowedLeadTimes.contains(v) {
                XCTAssertTrue(result, "Allowed value \(v) must be accepted")
                XCTAssertEqual(settings.leadTimeMinutes, v)
            } else {
                XCTAssertFalse(result, "Disallowed value \(v) must be rejected")
                XCTAssertEqual(
                    settings.leadTimeMinutes,
                    originalLead,
                    "Rejected setLeadTime must NOT mutate leadTimeMinutes"
                )
            }
        }
    }

    // MARK: - Property 21

    // Feature: task-time-and-notifications, Property 21: store fallback на default при невалидной/отсутствующей записи
    // Validates: Requirements 8.10
    //
    // Покрывает три варианта содержимого UserDefaults: отсутствие записи, произвольные
    // байты и валидный JSON с невалидным `leadTimeMinutes`.
    func testStoreFallsBackToDefaultOnInvalidData() {
        enum Variant {
            case missing
            case randomBytes
            case invalidLead
            case invalidMorning
        }

        let gen: () -> Variant = {
            let variants: [Variant] = [.missing, .randomBytes, .invalidLead, .invalidMorning]
            return variants.randomElement()!
        }

        PBT.forAll(gen, iterations: 40) { variant in
            let (defaults, _) = self.makeIsolatedDefaults()

            switch variant {
            case .missing:
                break

            case .randomBytes:
                let length = Int.random(in: 0...64)
                var bytes = [UInt8]()
                for _ in 0..<length {
                    bytes.append(UInt8.random(in: 0...255))
                }
                defaults.set(Data(bytes), forKey: "notification_settings")

            case .invalidLead:
                let invalid: [String: Any] = [
                    "morningDigestEnabled": true,
                    "morningTime": ["hour": 8, "minute": 0],
                    "taskRemindersEnabled": true,
                    "leadTimeMinutes": 7   // вне множества
                ]
                let data = try JSONSerialization.data(withJSONObject: invalid)
                defaults.set(data, forKey: "notification_settings")

            case .invalidMorning:
                let invalid: [String: Any] = [
                    "morningDigestEnabled": true,
                    "morningTime": ["hour": 99, "minute": 200],   // вне диапазонов
                    "taskRemindersEnabled": true,
                    "leadTimeMinutes": 15
                ]
                let data = try JSONSerialization.data(withJSONObject: invalid)
                defaults.set(data, forKey: "notification_settings")
            }

            let store = NotificationSettingsStore(defaults: defaults, fallback: defaults)
            XCTAssertEqual(
                store.settings,
                NotificationSettings.default,
                "Variant \(variant) must fall back to .default"
            )
        }
    }

    // MARK: - Unit: persist before publish

    // Unit-тест: store сначала пишет в UserDefaults, потом обновляет `@Published settings`.
    // _Requirements: 8.8_
    //
    // Проверяем синхронный contract: на момент эмиссии нового значения через
    // Combine sink уже есть сериализованная запись в UserDefaults.
    func testStorePersistsBeforeUpdatingSettings() throws {
        let (defaults, _) = makeIsolatedDefaults()
        let store = NotificationSettingsStore(defaults: defaults, fallback: defaults)

        var modified = NotificationSettings.default
        modified.morningTime = TimeOfDay(hour: 9, minute: 30)
        modified.taskRemindersEnabled = false
        modified.leadTimeMinutes = 30

        let expectation = self.expectation(description: "settings emitted with persistence ready")

        var cancellables = Set<AnyCancellable>()
        var sawInitial = false

        store.$settings
            .sink { value in
                // Первая эмиссия — текущее значение (default). Игнорируем её.
                if !sawInitial {
                    sawInitial = true
                    return
                }
                // Когда приходит новое значение — UserDefaults уже должен его содержать.
                XCTAssertEqual(value, modified)
                guard let data = defaults.data(forKey: "notification_settings") else {
                    XCTFail("UserDefaults must already contain serialized data at emission time")
                    expectation.fulfill()
                    return
                }
                do {
                    let decoded = try JSONDecoder().decode(NotificationSettings.self, from: data)
                    XCTAssertEqual(
                        decoded,
                        modified,
                        "Persisted JSON must match emitted value"
                    )
                } catch {
                    XCTFail("Persisted data must decode into NotificationSettings: \(error)")
                }
                expectation.fulfill()
            }
            .store(in: &cancellables)

        XCTAssertTrue(store.save(modified), "Save must succeed for valid settings")

        wait(for: [expectation], timeout: 1)
    }
}
