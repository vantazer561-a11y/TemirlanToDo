import SwiftUI
import WidgetKit

struct TodayWidgetSnapshot: Codable {
    var count: Int
    var titles: [String]
    var updatedAt: Date

    static let empty = TodayWidgetSnapshot(count: 0, titles: [], updatedAt: Date())
}

enum TodayWidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.temirlan.todo"
    private static let key = "today_widget_snapshot"

    static func load() -> TodayWidgetSnapshot {
        let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: key) ?? UserDefaults.standard.data(forKey: key)
        guard let data, let snapshot = try? JSONDecoder().decode(TodayWidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}

struct TodayTasksEntry: TimelineEntry {
    let date: Date
    let snapshot: TodayWidgetSnapshot
}

struct TodayTasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayTasksEntry {
        TodayTasksEntry(date: Date(), snapshot: TodayWidgetSnapshot(count: 3, titles: ["Ship IPA", "Test AI", "Plan tomorrow"], updatedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayTasksEntry) -> Void) {
        completion(TodayTasksEntry(date: Date(), snapshot: TodayWidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayTasksEntry>) -> Void) {
        let entry = TodayTasksEntry(date: Date(), snapshot: TodayWidgetSnapshotStore.load())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct TodayTasksWidgetView: View {
    let entry: TodayTasksEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.08),
                    Color(red: 0.10, green: 0.06, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Today", systemImage: "sun.max.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(entry.snapshot.count)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.13, green: 0.88, blue: 1.0))
                }

                if entry.snapshot.titles.isEmpty {
                    Text("Clear signal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.72))
                } else {
                    ForEach(entry.snapshot.titles.prefix(3), id: \.self) { title in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.16, blue: 0.72))
                                .frame(width: 5, height: 5)
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.86))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }
}

@main
struct TemirlanToDoWidget: Widget {
    let kind = "TemirlanToDoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayTasksProvider()) { entry in
            TodayTasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Today Tasks")
        .description("Shows today's active Temirlan To Do tasks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
