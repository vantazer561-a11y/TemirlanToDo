import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TaskItem
    @State private var hasDueDate: Bool
    @State private var hasDueTime: Bool

    init(task: TaskItem) {
        let initial = makeInitialDetailState(task)
        _draft = State(initialValue: task)
        _hasDueDate = State(initialValue: initial.hasDueDate)
        _hasDueTime = State(initialValue: initial.hasDueTime)
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
                        .onChange(of: hasDueDate) { newValue in
                            handleDueDateToggle(newValue)
                        }
                    Toggle("Add time", isOn: $hasDueTime)
                        .disabled(!hasDueDate)
                        .onChange(of: hasDueTime) { newValue in
                            handleDueTimeToggle(newValue)
                        }

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

                    if hasDueDate && hasDueTime {
                        DatePicker(
                            "Time",
                            selection: Binding(
                                get: { draft.dueDate ?? Date() },
                                set: { draft.dueDate = $0 }
                            ),
                            displayedComponents: .hourAndMinute
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

    /// Реакция на переключение `Due date`. _Requirements: 2.2, 2.3_
    private func handleDueDateToggle(_ newValue: Bool) {
        if newValue {
            if draft.dueDate == nil {
                draft.dueDate = Calendar.current.startOfDay(for: Date())
                draft.dueHasTime = false
                hasDueTime = false
            }
        } else {
            draft.dueDate = nil
            draft.dueHasTime = false
            hasDueTime = false
        }
    }

    /// Реакция на переключение `Add time`. _Requirements: 2.4, 2.6_
    private func handleDueTimeToggle(_ newValue: Bool) {
        if newValue, draft.dueDate != nil {
            draft.dueDate = nextRoundedQuarterHour(after: Date(), base: draft.dueDate)
            draft.dueHasTime = true
        } else if !newValue, let due = draft.dueDate {
            draft.dueDate = Calendar.current.startOfDay(for: due)
            draft.dueHasTime = false
        }
    }

    /// Сохраняет изменения. Финально согласовывает `dueDate`/`dueHasTime`
    /// с состоянием тумблеров и нормализует точность до минуты.
    /// _Requirements: 2.7, 1.5, 1.6, 1.7, 1.8_
    private func save() {
        if !hasDueDate {
            draft.dueDate = nil
            draft.dueHasTime = false
        } else if let due = draft.dueDate {
            if hasDueTime {
                // Нормализуем секунды/наносекунды у `dueDate`. _Requirements: 1.6_
                let calendar = Calendar.current
                let components = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: due
                )
                if let normalized = calendar.date(from: components) {
                    draft.dueDate = normalized
                }
                draft.dueHasTime = true
            } else {
                // Дата без времени — сбрасываем к началу локального дня. _Requirements: 1.7_
                draft.dueDate = Calendar.current.startOfDay(for: due)
                draft.dueHasTime = false
            }
        } else {
            // hasDueDate == true, но даты ещё нет — выставляем сегодняшнюю.
            draft.dueDate = Calendar.current.startOfDay(for: Date())
            draft.dueHasTime = false
        }
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateTask(draft)
        dismiss()
    }
}
