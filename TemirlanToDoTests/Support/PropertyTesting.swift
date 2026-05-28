import XCTest

/// Minimal property-based testing helper used by the test target.
///
/// We avoid pulling SwiftCheck via SPM (the project uses synthetic pbxproj IDs and we
/// want zero external test dependencies). `PBT.forAll` runs the supplied generator a
/// fixed number of iterations (default 100) and reports the failing input on any
/// thrown error, mirroring the QuickCheck-style API.
enum PBT {
    static let defaultIterations = 100

    static func forAll<A>(
        _ gen: () -> A,
        iterations: Int = defaultIterations,
        file: StaticString = #file,
        line: UInt = #line,
        _ check: (A) throws -> Void
    ) {
        for i in 0..<iterations {
            let value = gen()
            do {
                try check(value)
            } catch {
                XCTFail(
                    "Property failed at iteration \(i) with input: \(value). Error: \(error)",
                    file: file,
                    line: line
                )
                return
            }
        }
    }
}
