import SwiftUI

public enum TaskListKind: String, CaseIterable, Identifiable {
    case myDay
    case important
    case planned
    case tasks

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .myDay:
            return "My Day"
        case .important:
            return "Important"
        case .planned:
            return "Planned"
        case .tasks:
            return "Tasks"
        }
    }

    var subtitle: String {
        switch self {
        case .myDay:
            return "Today's signal"
        case .important:
            return "High-voltage priorities"
        case .planned:
            return "Scheduled work"
        case .tasks:
            return "All active tasks"
        }
    }

    var symbolName: String {
        switch self {
        case .myDay:
            return "sun.max.fill"
        case .important:
            return "star.fill"
        case .planned:
            return "calendar"
        case .tasks:
            return "checklist"
        }
    }

    var accentColor: Color {
        switch self {
        case .myDay:
            return CyberpunkTheme.cyan
        case .important:
            return CyberpunkTheme.magenta
        case .planned:
            return CyberpunkTheme.amber
        case .tasks:
            return CyberpunkTheme.mint
        }
    }

    func contains(_ task: TaskItem, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        switch self {
        case .myDay:
            if task.isInMyDay {
                return true
            }
            guard let dueDate = task.dueDate else {
                return false
            }
            return calendar.isDate(dueDate, inSameDayAs: now)
        case .important:
            return task.isImportant
        case .planned:
            return task.dueDate != nil
        case .tasks:
            return !task.isCompleted
        }
    }
}
