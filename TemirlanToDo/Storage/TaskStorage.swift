import Foundation

public struct TaskStorage {
    private let fileURL: URL?
    private let fileManager: FileManager

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public static func live(fileManager: FileManager = .default) -> TaskStorage {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TemirlanToDo", isDirectory: true)
        let fileURL = supportDirectory.appendingPathComponent("tasks.json")
        return TaskStorage(fileURL: fileURL, fileManager: fileManager)
    }

    public static func inMemory() -> TaskStorage {
        TaskStorage(fileURL: nil)
    }

    public func loadTasks() throws -> [TaskItem] {
        guard let fileURL else {
            return []
        }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([TaskItem].self, from: data)
    }

    public func saveTasks(_ tasks: [TaskItem]) throws {
        guard let fileURL else {
            return
        }
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tasks)
        try data.write(to: fileURL, options: [.atomic])
    }
}
