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
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Could not save the latest changes."
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
}
