import SwiftUI

struct AddTaskComposerView: View {
    @EnvironmentObject private var store: TaskStore
    let kind: TaskListKind

    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundColor(kind.accentColor)

            TextField("Add a task", text: $title)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(addTask)
                .foregroundColor(.white)

            Button(action: addTask) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(canSubmit ? kind.accentColor : .white.opacity(0.28))
            }
            .disabled(!canSubmit)
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassPanel(accent: kind.accentColor)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addTask() {
        guard canSubmit else {
            return
        }
        store.addTask(title: title, list: kind)
        title = ""
        isFocused = true
    }
}
