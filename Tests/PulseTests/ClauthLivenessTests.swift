import XCTest
@testable import Pulse

final class ClauthLivenessTests: XCTestCase {
    func testBandsOnTheOneSecondWriteCadence() {
        XCTAssertEqual(ClauthLiveness.freshness(ageSeconds: 0), .live)
        XCTAssertEqual(ClauthLiveness.freshness(ageSeconds: 4.9), .live)
        XCTAssertEqual(ClauthLiveness.freshness(ageSeconds: 5), .syncing)
        XCTAssertEqual(ClauthLiveness.freshness(ageSeconds: 14.9), .syncing)
        XCTAssertEqual(ClauthLiveness.freshness(ageSeconds: 15), .dead)
        XCTAssertEqual(ClauthLiveness.freshness(ageSeconds: 7200), .dead)
    }

    func testTheYoungerAgeIsTheEvidenceOfLife() {
        // Fresh mtime beside a stale (or skewed) generated_at ⇒ live.
        XCTAssertEqual(ClauthLiveness.freshness(generatedAtAge: 7200, statusMtimeAge: 1), .live)
        // And the reverse.
        XCTAssertEqual(ClauthLiveness.freshness(generatedAtAge: 1, statusMtimeAge: 7200), .live)
        XCTAssertEqual(ClauthLiveness.freshness(generatedAtAge: 8, statusMtimeAge: 20), .syncing)
    }

    func testOneUnknownAgeStillReads() {
        XCTAssertEqual(ClauthLiveness.freshness(generatedAtAge: nil, statusMtimeAge: 2), .live)
        XCTAssertEqual(ClauthLiveness.freshness(generatedAtAge: 30, statusMtimeAge: nil), .dead)
    }

    func testBothUnknownIsDead() {
        XCTAssertEqual(ClauthLiveness.freshness(generatedAtAge: nil, statusMtimeAge: nil), .dead)
    }

    func testTwoHoursOldOnBothClocksIsDead() {
        XCTAssertEqual(ClauthLiveness.freshness(generatedAtAge: 7200, statusMtimeAge: 7200), .dead)
    }
}
