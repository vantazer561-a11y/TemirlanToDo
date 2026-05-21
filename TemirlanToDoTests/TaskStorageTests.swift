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
}
