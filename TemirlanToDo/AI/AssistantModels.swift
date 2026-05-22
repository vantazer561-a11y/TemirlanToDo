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
        dueDate: String?
    ) {
        self.type = type
        self.taskId = taskId
        self.title = title
        self.notes = notes
        self.isImportant = isImportant
        self.isInMyDay = isInMyDay
        self.isCompleted = isCompleted
        self.dueDate = dueDate
    }
}

public enum AssistantActionType: String, Codable {
    case createTask = "create_task"
    case updateTask = "update_task"
    case deleteTask = "delete_task"
    case messageOnly = "message_only"
}

public struct OpenAIResponseEnvelope: Decodable {
    struct Output: Decodable {
        var content: [Content]?
    }

    struct Content: Decodable {
        var text: String?
    }

    var output: [Output]

    public var outputText: String? {
        output
            .compactMap(\.content)
            .flatMap { $0 }
            .compactMap(\.text)
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
                            "description": "ISO date in yyyy-MM-dd format."
                        ]
                    ]
                ]
            ]
        ]
    ]
}
