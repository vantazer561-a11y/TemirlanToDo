import Foundation

public final class AssistantService {
    private let client: OpenAIClient
    private let keychain: KeychainStore

    public init(client: OpenAIClient = OpenAIClient(), keychain: KeychainStore = .shared) {
        self.client = client
        self.keychain = keychain
    }

    public func hasAPIKey() -> Bool {
        do {
            return !(try keychain.loadAPIKey()?.isEmpty ?? true)
        } catch {
            return false
        }
    }

    public func saveAPIKey(_ key: String) throws {
        try keychain.saveAPIKey(key)
    }

    public func deleteAPIKey() throws {
        try keychain.deleteAPIKey()
    }

    public func ask(prompt: String, tasks: [TaskItem], mode: AssistantMode) async throws -> AssistantResponse {
        guard let apiKey = try keychain.loadAPIKey(), !apiKey.isEmpty else {
            throw AssistantServiceError.missingAPIKey
        }

        return try await client.sendAssistantRequest(
            apiKey: apiKey,
            developerPrompt: developerPrompt,
            userPrompt: userPrompt(prompt: prompt, tasks: tasks, mode: mode)
        )
    }

    private var developerPrompt: String {
        """
        You are the AI Assistant inside Temirlan To Do, a personal iOS task manager.
        Help the user plan tasks, split work into steps, improve wording, and organize today.
        Return only JSON that matches the provided schema.
        Do not claim that actions were applied. The app will preview actions first.
        Prefer concise Russian if the user writes Russian; otherwise follow the user's language.
        Use dueDate only as yyyy-MM-dd. Use taskId only for existing tasks included in context.
        Keep suggestions practical, small, and actionable.
        """
    }

    private func userPrompt(prompt: String, tasks: [TaskItem], mode: AssistantMode) -> String {
        """
        Assistant mode: \(mode.rawValue)

        User request:
        \(prompt)

        Current tasks:
        \(taskContext(tasks))
        """
    }

    private func taskContext(_ tasks: [TaskItem]) -> String {
        if tasks.isEmpty {
            return "No tasks yet."
        }

        return tasks.prefix(40).map { task in
            let due = task.dueDate.map { DateFormatter.assistantDate.string(from: $0) } ?? "none"
            return """
            - id: \(task.id.uuidString)
              title: \(task.title)
              notes: \(task.notes.isEmpty ? "none" : task.notes)
              completed: \(task.isCompleted)
              important: \(task.isImportant)
              myDay: \(task.isInMyDay)
              dueDate: \(due)
            """
        }
        .joined(separator: "\n")
    }
}

public enum AssistantMode: String, CaseIterable, Identifiable {
    case general = "General"
    case breakDown = "Break task into steps"
    case planDay = "Plan my day"
    case createTasks = "Create tasks from text"
    case improveWording = "Improve task wording"

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "Ask"
        case .breakDown:
            return "Break down"
        case .planDay:
            return "Plan day"
        case .createTasks:
            return "Create tasks"
        case .improveWording:
            return "Improve"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            return "sparkles"
        case .breakDown:
            return "list.bullet.indent"
        case .planDay:
            return "sun.max"
        case .createTasks:
            return "plus.square.on.square"
        case .improveWording:
            return "text.bubble"
        }
    }
}

public enum AssistantServiceError: LocalizedError {
    case missingAPIKey

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Save an OpenAI API key before using the assistant."
        }
    }
}

private extension DateFormatter {
    static let assistantDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
