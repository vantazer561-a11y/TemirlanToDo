import XCTest
@testable import TemirlanToDo

final class AssistantModelsTests: XCTestCase {
    func testAssistantResponseDecodesActions() throws {
        let json = """
        {
          "message": "I prepared a launch plan.",
          "actions": [
            {
              "type": "create_task",
              "title": "Draft release checklist",
              "notes": "Cover build, install, and smoke test.",
              "isImportant": true,
              "isInMyDay": true,
              "dueDate": "2026-05-23"
            },
            {
              "type": "message_only",
              "title": null,
              "notes": "Keep the scope small.",
              "isImportant": null,
              "isInMyDay": null,
              "dueDate": null
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(AssistantResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.message, "I prepared a launch plan.")
        XCTAssertEqual(response.actions.count, 2)
        XCTAssertEqual(response.actions.first?.type, .createTask)
        XCTAssertEqual(response.actions.first?.title, "Draft release checklist")
        XCTAssertEqual(response.actions.first?.dueDate, "2026-05-23")
        XCTAssertEqual(response.actions.last?.type, .messageOnly)
    }

    func testFireworksChatCompletionEnvelopeExtractsOutputText() throws {
        let json = """
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "{\\"message\\":\\"Done\\",\\"actions\\":[]}"
              }
            }
          ]
        }
        """

        let envelope = try JSONDecoder().decode(FireworksChatCompletionEnvelope.self, from: Data(json.utf8))

        XCTAssertEqual(envelope.outputText, "{\"message\":\"Done\",\"actions\":[]}")
    }
}
