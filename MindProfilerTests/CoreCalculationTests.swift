import XCTest
@testable import MindProfiler

final class CoreCalculationTests: XCTestCase {
    func testActualSleepDurationExcludesGapInsideMergedRange() {
        let start = Date(timeIntervalSince1970: 0)
        let range = SleepRange(
            start: start,
            end: start.addingTimeInterval(3 * 3_600),
            stageDurations: [.core: 3_600, .rem: 1_800],
            estimatedScore: 70
        )

        XCTAssertEqual(range.actualSleepDuration, 5_400)
        XCTAssertNotEqual(range.actualSleepDuration, range.end.timeIntervalSince(range.start))
    }

    func testMedianForEvenAndOddValueCounts() {
        XCTAssertEqual(HRVStatistics.median([3, 1, 2]), 2)
        XCTAssertEqual(HRVStatistics.median([4, 1, 3, 2]), 2.5)
    }

    func testPearsonCorrelationDirection() throws {
        let correlation = try XCTUnwrap(
            HRVStatistics.pearsonCorrelation([(1, 3), (2, 2), (3, 1)])
        )

        XCTAssertEqual(correlation, -1, accuracy: 0.000_001)
    }
}
