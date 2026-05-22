import Foundation

public struct TodayWidgetSnapshot: Codable, Equatable {
    public var count: Int
    public var titles: [String]
    public var updatedAt: Date

    public init(count: Int, titles: [String], updatedAt: Date = Date()) {
        self.count = count
        self.titles = titles
        self.updatedAt = updatedAt
    }

    public static let empty = TodayWidgetSnapshot(count: 0, titles: [])
}

public enum TodayWidgetSnapshotStore {
    public static let appGroupIdentifier = "group.com.temirlan.todo"
    private static let key = "today_widget_snapshot"

    public static func save(_ snapshot: TodayWidgetSnapshot, userDefaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        userDefaults.set(data, forKey: key)
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: key)
    }

    public static func load(userDefaults: UserDefaults = .standard) -> TodayWidgetSnapshot {
        let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: key) ?? userDefaults.data(forKey: key)
        guard let data, let snapshot = try? JSONDecoder().decode(TodayWidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}
