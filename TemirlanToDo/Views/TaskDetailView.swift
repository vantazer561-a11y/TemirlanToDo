import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TaskItem
    @State private var hasDueDate: Bool

    init(task: TaskItem) {
        _draft = State(initialValue: task)
        _hasDueDate = State(initialValue: task.dueDate != nil)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Task") {
                    TextField("Title", text: $draft.title)
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 110)
                }

                Section("Signals") {
                    Toggle("Completed", isOn: $draft.isCompleted)
                    Toggle("Important", isOn: $draft.isImportant)
                    Toggle("My Day", isOn: $draft.isInMyDay)
                    Toggle("Due date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker(
                            "Date",
                            selection: Binding(
                                get: { draft.dueDate ?? Date() },
                                set: { draft.dueDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                    }
                }

                Section {
                    Button(role: .destructive) {
                        store.deleteTask(draft.id)
                        dismiss()
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        if !hasDueDate {
            draft.dueDate = nil
        } else if draft.dueDate == nil {
            draft.dueDate = Date()
        }
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateTask(draft)
        dismiss()
    }
}
