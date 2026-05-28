import XCTest
@testable import TemirlanToDo

final class TaskStorageTests: XCTestCase {
    func testStorageSavesAndLoadsTasks() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let storage = TaskStorage(fileURL: url)
        let task = TaskItem(title: "Persist the signal", notes: "Survive restart.", isImportant: true)

        try storage.saveTasks([task])
        let loaded = try storage.loadTasks()

        XCTAssertEqual(loaded, [task])
        try? FileManager.default.removeItem(at: url)
    }

    func testStorageReturnsEmptyArrayForMissingFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let storage = TaskStorage(fileURL: url)

        XCTAssertEqual(try storage.loadTasks(), [])
    }

    // Feature: task-time-and-notifications, Property 1: TaskItem JSON round-trip с миграцией
    // Validates: Requirements 1.2, 10.3, 10.4
    func testJSONRoundTripPreservesTaskItem() {
        PBT.forAll(generateTaskItem) { task in
            let data = try JSONEncoder().encode(task)
            let decoded = try JSONDecoder().decode(TaskItem.self, from: data)
            XCTAssertEqual(decoded, task)
        }
    }
}
