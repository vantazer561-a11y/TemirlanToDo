import XCTest
@testable import TemirlanToDo

final class AssistantActionsTests: XCTestCase {
    func testApplyAssistantActionsCreatesUpdatesAndDeletesTasks() {
        let store = TaskStore(storage: .inMemory())
        let created = store.addTask(title: "Old title", list: .tasks)
        let deleted = store.addTask(title: "Delete me", list: .tasks)

        let actions = [
            AssistantAction(
                type: .createTask,
                taskId: nil,
                title: "New AI task",
                notes: "Generated notes",
                isImportant: true,
                isInMyDay: true,
                isCompleted: nil,
                dueDate: "2026-05-24"
            ),
            AssistantAction(
                type: .updateTask,
                taskId: created.id.uuidString,
                title: "Updated title",
                notes: "Updated notes",
                isImportant: true,
                isInMyDay: nil,
                isCompleted: true,
                dueDate: nil
            ),
            AssistantAction(
                type: .deleteTask,
                taskId: deleted.id.uuidString,
                title: nil,
                notes: nil,
                isImportant: nil,
                isInMyDay: nil,
                isCompleted: nil,
                dueDate: nil
            )
        ]

        store.applyAssistantActions(actions, calendar: Calendar(identifier: .gregorian))

        XCTAssertNil(store.tasks.first { $0.id == deleted.id })
        XCTAssertEqual(store.tasks.first { $0.id == created.id }?.title, "Updated title")
        XCTAssertTrue(store.tasks.first { $0.id == created.id }?.isCompleted == true)
        XCTAssertTrue(store.tasks.contains { $0.title == "New AI task" && $0.isImportant && $0.isInMyDay })
        XCTAssertNotNil(store.tasks.first { $0.title == "New AI task" }?.dueDate)
    }
}
