import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        NavigationView {
            ZStack {
                CyberpunkTheme.backgroundGradient
                    .ignoresSafeArea()

                List {
                    Section {
                        ForEach(TaskListKind.allCases) { kind in
                            NavigationLink(destination: TaskListView(kind: kind)) {
                                SmartListRow(kind: kind, count: store.tasks(for: kind).count)
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Temirlan To Do")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Focus board with a neon pulse")
                                .font(.subheadline)
                                .foregroundColor(CyberpunkTheme.softText)
                        }
                        .textCase(nil)
                        .padding(.vertical, 12)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationBarHidden(true)

            TaskListView(kind: .myDay)
        }
        .accentColor(CyberpunkTheme.cyan)
    }
}

private struct SmartListRow: View {
    let kind: TaskListKind
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(kind.accentColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: kind.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(kind.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.headline)
                Text(kind.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(kind.accentColor)
        }
        .padding(.vertical, 6)
    }
}
