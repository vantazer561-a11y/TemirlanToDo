import Foundation

public struct TaskItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var isCompleted: Bool
    public var isImportant: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var dueDate: Date?
    public var isInMyDay: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        isCompleted: Bool = false,
        isImportant: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        dueDate: Date? = nil,
        isInMyDay: Bool = false
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.isImportant = isImportant
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dueDate = dueDate
        self.isInMyDay = isInMyDay
    }
}
