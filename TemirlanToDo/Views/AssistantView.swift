import SwiftUI

struct AssistantView: View {
    @EnvironmentObject private var store: TaskStore

    private let service = AssistantService()

    @State private var hasAPIKey = false
    @State private var prompt = ""
    @State private var selectedMode: AssistantMode = .general
    @State private var response: AssistantResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            CyberpunkTheme.backgroundGradient
                .ignoresSafeArea()

            if hasAPIKey {
                assistantContent
            } else {
                AISettingsView(service: service) {
                    hasAPIKey = service.hasAPIKey()
                }
            }
        }
        .navigationTitle("AI Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasAPIKey {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationView {
                AISettingsManagementView(service: service) {
                    hasAPIKey = service.hasAPIKey()
                    showingSettings = false
                }
            }
        }
        .onAppear {
            hasAPIKey = service.hasAPIKey()
        }
    }

    private var assistantContent: some View {
        VStack(spacing: 14) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    quickActions
                    promptBox

                    if isLoading {
                        ProgressView("Thinking")
                            .progressViewStyle(.circular)
                            .tint(CyberpunkTheme.cyan)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(18)
                            .glassPanel(accent: CyberpunkTheme.cyan)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(CyberpunkTheme.magenta)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassPanel(accent: CyberpunkTheme.magenta)
                    }

                    if let response {
                        responsePreview(response)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.bold))
                    .foregroundColor(CyberpunkTheme.cyan)
                Text("AI Assistant")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }

            Text("Plan, split, and shape tasks before applying changes.")
                .font(.subheadline)
                .foregroundColor(CyberpunkTheme.softText)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(AssistantMode.allCases.filter { $0 != .general }) { mode in
                Button {
                    selectedMode = mode
                    if prompt.isEmpty {
                        prompt = defaultPrompt(for: mode)
                    }
                } label: {
                    Label(mode.title, systemImage: mode.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundColor(selectedMode == mode ? .black : .white)
                .background(selectedMode == mode ? CyberpunkTheme.cyan : CyberpunkTheme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var promptBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $prompt)
                .frame(minHeight: 110)
                .foregroundColor(.white)
                .background(Color.clear)
                .overlay(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("Ask what to plan...")
                            .foregroundColor(CyberpunkTheme.softText)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                }

            Button {
                askAssistant()
            } label: {
                Label("Ask Assistant", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(CyberpunkTheme.cyan)
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .padding(14)
        .glassPanel(accent: CyberpunkTheme.cyan)
    }

    private func responsePreview(_ response: AssistantResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(response.message)
                .font(.body)
                .foregroundColor(.white)

            ForEach(response.actions) { action in
                actionRow(action)
            }

            if response.actions.contains(where: { $0.type != .messageOnly }) {
                HStack {
                    Button {
                        self.response = nil
                    } label: {
                        Label("Discard", systemImage: "xmark")
                    }
                    .foregroundColor(CyberpunkTheme.softText)

                    Spacer()

                    Button {
                        store.applyAssistantActions(response.actions)
                        self.response = nil
                    } label: {
                        Label("Apply", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                    }
                    .foregroundColor(CyberpunkTheme.mint)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .glassPanel(accent: CyberpunkTheme.magenta)
    }

    private func actionRow(_ action: AssistantAction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: action.type))
                .foregroundColor(color(for: action.type))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(action.title ?? action.notes ?? action.type.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                if let notes = action.notes, action.title != nil {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(CyberpunkTheme.softText)
                }
                if let dueDate = action.dueDate {
                    Text("Due: \(dueDate)")
                        .font(.caption)
                        .foregroundColor(CyberpunkTheme.amber)
                }
            }
        }
        .padding(10)
        .background(CyberpunkTheme.elevated.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func askAssistant() {
        isLoading = true
        errorMessage = nil
        response = nil

        Task {
            do {
                let result = try await service.ask(prompt: prompt, tasks: store.tasks, mode: selectedMode)
                await MainActor.run {
                    response = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func defaultPrompt(for mode: AssistantMode) -> String {
        switch mode {
        case .general:
            return ""
        case .breakDown:
            return "Разбей эту задачу на понятные шаги: "
        case .planDay:
            return "Составь план на сегодня из моих текущих задач."
        case .createTasks:
            return "Создай задачи из этого текста: "
        case .improveWording:
            return "Улучши формулировку этой задачи: "
        }
    }

    private func iconName(for type: AssistantActionType) -> String {
        switch type {
        case .createTask:
            return "plus.circle.fill"
        case .updateTask:
            return "pencil.circle.fill"
        case .deleteTask:
            return "trash.circle.fill"
        case .messageOnly:
            return "text.bubble.fill"
        }
    }

    private func color(for type: AssistantActionType) -> Color {
        switch type {
        case .createTask:
            return CyberpunkTheme.mint
        case .updateTask:
            return CyberpunkTheme.cyan
        case .deleteTask:
            return CyberpunkTheme.magenta
        case .messageOnly:
            return CyberpunkTheme.amber
        }
    }
}

private struct AISettingsManagementView: View {
    let service: AssistantService
    let onChange: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AISettingsView(service: service, onSaved: onChange)

            Button(role: .destructive) {
                deleteKey()
            } label: {
                Label("Delete saved API key", systemImage: "trash")
                    .padding(.horizontal, 20)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(CyberpunkTheme.magenta)
                    .padding(.horizontal, 20)
            }
        }
        .background(CyberpunkTheme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("AI Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteKey() {
        do {
            try service.deleteAPIKey()
            onChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
