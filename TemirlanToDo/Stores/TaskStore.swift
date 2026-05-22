import Combine
import Foundation

public final class TaskStore: ObservableObject {
    @Published public private(set) var tasks: [TaskItem]
    @Published public var lastErrorMessage: String?

    private let storage: TaskStorage

    public init(storage: TaskStorage = .live()) {
        self.storage = storage
        do {
            self.tasks = try storage.loadTasks()
        } catch {
            self.tasks = []
            self.lastErrorMessage = "Could not load saved tasks."
        }
    }

    @discardableResult
    public func addTask(title: String, list: TaskListKind) -> TaskItem {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return TaskItem(title: "")
        }

        var task = TaskItem(title: trimmedTitle)
        applyDefaults(for: list, to: &task)
        tasks.insert(task, at: 0)
        save()
        return task
    }

    public func updateTask(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return
        }
        var updated = task
        updated.updatedAt = Date()
        tasks[index] = updated
        save()
    }

    public func deleteTask(_ id: TaskItem.ID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    public func toggleCompletion(for id: TaskItem.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        tasks[index].isCompleted.toggle()
        tasks[index].updatedAt = Date()
        save()
    }

    public func toggleImportance(for id: TaskItem.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }
        tasks[index].isImportant.toggle()
        tasks[index].updatedAt = Date()
        save()
    }

    public func tasks(for list: TaskListKind, calendar: Calendar = .current) -> [TaskItem] {
        tasks
            .filter { list.contains($0, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    public func save() {
        do {
            try storage.saveTasks(tasks)
            saveTodayWidgetSnapshot()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Could not save the latest changes."
        }
    }

    public func applyAssistantActions(_ actions: [AssistantAction], calendar: Calendar = .current) {
        var changed = false
        for action in actions {
            switch action.type {
            case .createTask:
                guard let title = action.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                    continue
                }
                var task = TaskItem(title: title)
                task.notes = action.notes ?? ""
                task.isImportant = action.isImportant ?? false
                task.isInMyDay = action.isInMyDay ?? false
                task.isCompleted = action.isCompleted ?? false
                task.dueDate = date(from: action.dueDate, calendar: calendar)
                tasks.insert(task, at: 0)
                changed = true

            case .updateTask:
                guard
                    let idString = action.taskId,
                    let id = UUID(uuidString: idString),
                    let index = tasks.firstIndex(where: { $0.id == id })
                else {
                    continue
                }
                if let title = action.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    tasks[index].title = title
                }
                if let notes = action.notes {
                    tasks[index].notes = notes
                }
                if let isImportant = action.isImportant {
                    tasks[index].isImportant = isImportant
                }
                if let isInMyDay = action.isInMyDay {
                    tasks[index].isInMyDay = isInMyDay
                }
                if let isCompleted = action.isCompleted {
                    tasks[index].isCompleted = isCompleted
                }
                if action.dueDate != nil {
                    tasks[index].dueDate = date(from: action.dueDate, calendar: calendar)
                }
                tasks[index].updatedAt = Date()
                changed = true

            case .deleteTask:
                guard let idString = action.taskId, let id = UUID(uuidString: idString) else {
                    continue
                }
                let originalCount = tasks.count
                tasks.removeAll { $0.id == id }
                changed = changed || tasks.count != originalCount

            case .messageOnly:
                continue
            }
        }

        if changed {
            save()
        }
    }

    private func applyDefaults(for list: TaskListKind, to task: inout TaskItem) {
        switch list {
        case .myDay:
            task.isInMyDay = true
        case .important:
            task.isImportant = true
        case .planned:
            task.dueDate = Date()
        case .tasks:
            break
        }
    }

    private func date(from value: String?, calendar: Calendar) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func saveTodayWidgetSnapshot(calendar: Calendar = .current) {
        let todayTasks = tasks
            .filter { !$0.isCompleted && TaskListKind.myDay.contains($0, calendar: calendar) }
            .prefix(3)
        let allTodayCount = tasks.filter { !$0.isCompleted && TaskListKind.myDay.contains($0, calendar: calendar) }.count
        TodayWidgetSnapshotStore.save(TodayWidgetSnapshot(
            count: allTodayCount,
            titles: todayTasks.map(\.title)
        ))
    }
}
