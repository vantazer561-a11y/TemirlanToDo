import XCTest
@testable import TemirlanToDo

final class TaskStoreTests: XCTestCase {
    func testAddTaskStoresTitleAndMyDayFlag() {
        let store = TaskStore(storage: .inMemory())

        let task = store.addTask(title: "Plan the neon sprint", list: .myDay)

        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(task.title, "Plan the neon sprint")
        XCTAssertTrue(task.isInMyDay)
        XCTAssertFalse(task.isCompleted)
    }

    func testSmartListsFilterTasks() {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let store = TaskStore(storage: .inMemory())

        let myDay = store.addTask(title: "Today focus", list: .myDay)
        _ = store.addTask(title: "Critical launch", list: .important)
        var planned = store.addTask(title: "Tomorrow release", list: .planned)
        planned.dueDate = tomorrow
        store.updateTask(planned)
        store.toggleCompletion(for: myDay.id)

        XCTAssertEqual(store.tasks(for: .myDay, calendar: calendar).map(\.title), ["Today focus"])
        XCTAssertEqual(store.tasks(for: .important, calendar: calendar).map(\.title), ["Critical launch"])
        XCTAssertEqual(store.tasks(for: .planned, calendar: calendar).map(\.title), ["Tomorrow release"])
        XCTAssertEqual(store.tasks(for: .tasks, calendar: calendar).map(\.title), ["Tomorrow release", "Critical launch"])
    }

    func testUpdateToggleAndDeleteTask() {
        let store = TaskStore(storage: .inMemory())
        var task = store.addTask(title: "Draft task", list: .tasks)

        task.title = "Polished task"
        task.notes = "Looks sharp."
        task.isImportant = true
        store.updateTask(task)
        store.toggleCompletion(for: task.id)
        store.toggleImportance(for: task.id)

        XCTAssertEqual(store.tasks.first?.title, "Polished task")
        XCTAssertEqual(store.tasks.first?.notes, "Looks sharp.")
        XCTAssertTrue(store.tasks.first?.isCompleted == true)
        XCTAssertFalse(store.tasks.first?.isImportant == true)

        store.deleteTask(task.id)
        XCTAssertTrue(store.tasks.isEmpty)
    }
}
