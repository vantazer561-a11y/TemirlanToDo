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
    public var dueHasTime: Bool
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
        dueHasTime: Bool = false,
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
        self.dueHasTime = dueHasTime
        self.isInMyDay = isInMyDay
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case isCompleted
        case isImportant
        case createdAt
        case updatedAt
        case dueDate
        case dueHasTime
        case isInMyDay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let title = try container.decode(String.self, forKey: .title)
        let notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        let isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        let isImportant = try container.decodeIfPresent(Bool.self, forKey: .isImportant) ?? false
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        let dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        let rawDueHasTime = try container.decodeIfPresent(Bool.self, forKey: .dueHasTime) ?? false
        let dueHasTime = (dueDate == nil) ? false : rawDueHasTime
        let isInMyDay = try container.decodeIfPresent(Bool.self, forKey: .isInMyDay) ?? false

        self.init(
            id: id,
            title: title,
            notes: notes,
            isCompleted: isCompleted,
            isImportant: isImportant,
            createdAt: createdAt,
            updatedAt: updatedAt,
            dueDate: dueDate,
            dueHasTime: dueHasTime,
            isInMyDay: isInMyDay
        )
    }
}
