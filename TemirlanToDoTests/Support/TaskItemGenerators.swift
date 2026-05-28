import Foundation
@testable import TemirlanToDo

/// Random `TaskItem` generator for property-based tests.
///
/// All `Date` fields are anchored to integer seconds since 1970 so that the value
/// survives JSON round-trip exactly under `JSONEncoder.DateEncodingStrategy.deferredToDate`
/// (which encodes a `Double` of `timeIntervalSinceReferenceDate`). The generator covers
/// three structural variants: `dueDate == nil`, `dueDate != nil` with `dueHasTime == false`,
/// and `dueDate != nil` with `dueHasTime == true`. The combination
/// `dueDate == nil && dueHasTime == true` is forbidden by the decoder invariant
/// (see `TaskItem.init(from:)`) so it is never produced.
func generateTaskItem() -> TaskItem {
    let dueVariant = Int.random(in: 0...2)
    let dueDate: Date?
    let dueHasTime: Bool
    switch dueVariant {
    case 0:
        dueDate = nil
        dueHasTime = false
    case 1:
        dueDate = generateIntegerSecondDate()
        dueHasTime = false
    default:
        dueDate = generateIntegerSecondDate()
        dueHasTime = true
    }

    return TaskItem(
        id: UUID(),
        title: generateRandomString(maxLength: 32),
        notes: generateRandomString(maxLength: 64),
        isCompleted: Bool.random(),
        isImportant: Bool.random(),
        createdAt: generateIntegerSecondDate(),
        updatedAt: generateIntegerSecondDate(),
        dueDate: dueDate,
        dueHasTime: dueHasTime,
        isInMyDay: Bool.random()
    )
}

/// Generates a `Date` whose `timeIntervalSince1970` is an integer in [0, 4_000_000_000].
/// Avoids fractional seconds so the value is preserved exactly across JSON encode/decode.
func generateIntegerSecondDate() -> Date {
    Date(timeIntervalSince1970: TimeInterval(Int.random(in: 0...4_000_000_000)))
}

/// Generates a random String of length 0..<=`maxLength` from a small printable alphabet.
func generateRandomString(maxLength: Int) -> String {
    let length = Int.random(in: 0...max(0, maxLength))
    let alphabet: [Character] = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_.,!?")
    var result = ""
    result.reserveCapacity(length)
    for _ in 0..<length {
        result.append(alphabet.randomElement()!)
    }
    return result
}
