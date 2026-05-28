import XCTest
@testable import TemirlanToDo

final class AssistantSchemaTests: XCTestCase {
    /// Snapshot-тест: схема описывает оба формата `dueDate`.
    /// _Requirements: 4.5_
    func testSchemaDescribesBothFormatsForDueDate() throws {
        let schema = AssistantSchema.json

        guard
            let properties = schema["properties"] as? [String: Any],
            let actions = properties["actions"] as? [String: Any],
            let items = actions["items"] as? [String: Any],
            let itemProps = items["properties"] as? [String: Any],
            let dueDate = itemProps["dueDate"] as? [String: Any]
        else {
            XCTFail("AssistantSchema.json structure missing properties.actions.items.properties.dueDate")
            return
        }

        // type содержит string и null.
        guard let types = dueDate["type"] as? [String] else {
            XCTFail("dueDate.type must be an array of strings")
            return
        }
        XCTAssertTrue(types.contains("string"))
        XCTAssertTrue(types.contains("null"))

        // pattern.
        let pattern = dueDate["pattern"] as? String
        XCTAssertEqual(
            pattern,
            #"^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2})?$"#,
            "dueDate.pattern must accept both yyyy-MM-dd and yyyy-MM-dd'T'HH:mm"
        )

        // description содержит обе подстроки форматов.
        guard let description = dueDate["description"] as? String else {
            XCTFail("dueDate.description missing")
            return
        }
        XCTAssertTrue(
            description.contains("yyyy-MM-dd"),
            "dueDate.description must mention yyyy-MM-dd"
        )
        XCTAssertTrue(
            description.contains("yyyy-MM-dd'T'HH:mm"),
            "dueDate.description must mention yyyy-MM-dd'T'HH:mm"
        )
    }
}
