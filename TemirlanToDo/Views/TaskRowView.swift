import SwiftUI

struct TaskRowView: View {
    let task: TaskItem
    let accent: Color
    let onComplete: () -> Void
    let onImportant: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(task.isCompleted ? accent : .white.opacity(0.78))
            }
            .buttonStyle(.plain)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .strikethrough(task.isCompleted, color: CyberpunkTheme.softText)
                    if !task.notes.isEmpty || task.dueDate != nil || task.isInMyDay {
                        HStack(spacing: 8) {
                            if task.isInMyDay {
                                Label("My Day", systemImage: "sun.max")
                            }
                            if let dueDate = task.dueDate {
                                Label(
                                    formattedDue(date: dueDate, hasTime: task.dueHasTime),
                                    systemImage: "calendar"
                                )
                            }
                            if !task.notes.isEmpty {
                                Image(systemName: "note.text")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(CyberpunkTheme.softText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: onImportant) {
                Image(systemName: task.isImportant ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .foregroundColor(task.isImportant ? CyberpunkTheme.magenta : .white.opacity(0.62))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassPanel(accent: task.isImportant ? CyberpunkTheme.magenta : accent)
        .opacity(task.isCompleted ? 0.72 : 1)
    }
}
