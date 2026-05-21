import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var store: TaskStore
    let kind: TaskListKind

    @State private var searchText = ""
    @State private var editingTask: TaskItem?
    @State private var showingCompleted = false

    private var filteredTasks: [TaskItem] {
        let source = store.tasks(for: kind)
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return source
        }
        return source.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var activeTasks: [TaskItem] {
        filteredTasks.filter { !$0.isCompleted }
    }

    private var completedTasks: [TaskItem] {
        filteredTasks.filter(\.isCompleted)
    }

    var body: some View {
        ZStack {
            CyberpunkTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 14) {
                header

                ScrollView {
                    LazyVStack(spacing: 10) {
                        if activeTasks.isEmpty && completedTasks.isEmpty {
                            emptyState
                        }

                        ForEach(activeTasks) { task in
                            TaskRowView(task: task, accent: kind.accentColor) {
                                store.toggleCompletion(for: task.id)
                            } onImportant: {
                                store.toggleImportance(for: task.id)
                            } onOpen: {
                                editingTask = task
                            }
                        }

                        if !completedTasks.isEmpty {
                            completedHeader

                            if showingCompleted {
                                ForEach(completedTasks) { task in
                                    TaskRowView(task: task, accent: kind.accentColor) {
                                        store.toggleCompletion(for: task.id)
                                    } onImportant: {
                                        store.toggleImportance(for: task.id)
                                    } onOpen: {
                                        editingTask = task
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
                }
            }

            VStack {
                Spacer()
                AddTaskComposerView(kind: kind)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .sheet(item: $editingTask) { task in
            TaskDetailView(task: task)
                .environmentObject(store)
        }
        .alert(isPresented: Binding(
            get: { store.lastErrorMessage != nil },
            set: { if !$0 { store.lastErrorMessage = nil } }
        )) {
            Alert(
                title: Text("Storage issue"),
                message: Text(store.lastErrorMessage ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: kind.symbolName)
                    .font(.title2.weight(.bold))
                    .foregroundColor(kind.accentColor)
                Text(kind.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }

            Text(kind.subtitle)
                .font(.subheadline)
                .foregroundColor(CyberpunkTheme.softText)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(kind.accentColor)
            Text("Clear signal")
                .font(.headline)
                .foregroundColor(.white)
            Text("Add a task and keep the day moving.")
                .font(.subheadline)
                .foregroundColor(CyberpunkTheme.softText)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .glassPanel(accent: kind.accentColor)
    }

    private var completedHeader: some View {
        Button {
            withAnimation(.spring()) {
                showingCompleted.toggle()
            }
        } label: {
            HStack {
                Text("Completed")
                    .font(.headline)
                Spacer()
                Text("\(completedTasks.count)")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: showingCompleted ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .foregroundColor(.white)
            .padding()
            .glassPanel(accent: kind.accentColor)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}
