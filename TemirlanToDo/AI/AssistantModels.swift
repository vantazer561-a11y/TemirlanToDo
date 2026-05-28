import Foundation

public struct AssistantResponse: Codable, Equatable {
    public var message: String
    public var actions: [AssistantAction]

    public init(message: String, actions: [AssistantAction]) {
        self.message = message
        self.actions = actions
    }
}

public struct AssistantAction: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var type: AssistantActionType
    public var taskId: String?
    public var title: String?
    public var notes: String?
    public var isImportant: Bool?
    public var isInMyDay: Bool?
    public var isCompleted: Bool?
    public var dueDate: String?
    /// Флаг, означающий «ключ `dueDate` присутствовал в JSON». Используется, чтобы
    /// отличить семантику «оставить значение неизменным» (ключ отсутствует) от
    /// «очистить значение» (ключ присутствует и равен `null`). Свойство не кодируется
    /// обратно в JSON — его наличие нужно только при декодировании входа от модели.
    public private(set) var dueDateProvided: Bool

    enum CodingKeys: String, CodingKey {
        case type
        case taskId
        case title
        case notes
        case isImportant
        case isInMyDay
        case isCompleted
        case dueDate
    }

    public init(
        type: AssistantActionType,
        taskId: String?,
        title: String?,
        notes: String?,
        isImportant: Bool?,
        isInMyDay: Bool?,
        isCompleted: Bool?,
        dueDate: String?,
        dueDateProvided: Bool = true
    ) {
        self.type = type
        self.taskId = taskId
        self.title = title
        self.notes = notes
        self.isImportant = isImportant
        self.isInMyDay = isInMyDay
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.dueDateProvided = dueDateProvided
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(AssistantActionType.self, forKey: .type)
        self.taskId = try container.decodeIfPresent(String.self, forKey: .taskId)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.isImportant = try container.decodeIfPresent(Bool.self, forKey: .isImportant)
        self.isInMyDay = try container.decodeIfPresent(Bool.self, forKey: .isInMyDay)
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted)
        // Семантика: ключ отсутствует → не трогать; ключ `null` → очистить;
        // ключ-строка → парсить (см. TaskStore.parseAssistantDueDate / applyAssistantActions).
        self.dueDateProvided = container.contains(.dueDate)
        self.dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
    }
}

public enum AssistantActionType: String, Codable {
    case createTask = "create_task"
    case updateTask = "update_task"
    case deleteTask = "delete_task"
    case messageOnly = "message_only"
}

public struct FireworksChatCompletionEnvelope: Decodable {
    struct Choice: Decodable {
        var message: Message?
    }

    struct Message: Decodable {
        var content: String?
    }

    var choices: [Choice]

    public var outputText: String? {
        choices
            .compactMap { $0.message?.content }
            .first
    }
}

enum AssistantSchema {
    static let json: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["message", "actions"],
        "properties": [
            "message": [
                "type": "string",
                "description": "A concise Russian or user-language explanation of the suggestions."
            ],
            "actions": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": [
                        "type",
                        "taskId",
                        "title",
                        "notes",
                        "isImportant",
                        "isInMyDay",
                        "isCompleted",
                        "dueDate"
                    ],
                    "properties": [
                        "type": [
                            "type": "string",
                            "enum": ["create_task", "update_task", "delete_task", "message_only"]
                        ],
                        "taskId": [
                            "type": ["string", "null"],
                            "description": "Existing task UUID for update_task or delete_task."
                        ],
                        "title": [
                            "type": ["string", "null"]
                        ],
                        "notes": [
                            "type": ["string", "null"]
                        ],
                        "isImportant": [
                            "type": ["boolean", "null"]
                        ],
                        "isInMyDay": [
                            "type": ["boolean", "null"]
                        ],
                        "isCompleted": [
                            "type": ["boolean", "null"]
                        ],
                        "dueDate": [
                            "type": ["string", "null"],
                            "pattern": "^\\d{4}-\\d{2}-\\d{2}(T\\d{2}:\\d{2})?$",
                            "description": "ISO date 'yyyy-MM-dd' or ISO date-time 'yyyy-MM-dd'T'HH:mm' (local timezone, 24-hour). null clears the due date."
                        ]
                    ]
                ]
            ]
        ]
    ]
}
