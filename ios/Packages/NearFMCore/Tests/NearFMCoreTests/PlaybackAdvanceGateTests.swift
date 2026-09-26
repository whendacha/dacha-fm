import XCTest
@testable import NearFMCore

final class PlaybackAdvanceGateTests: XCTestCase {
    func testLatePageCannotAdvanceAfterUserChangesPlaybackIntent() {
        var gate = PlaybackAdvanceGate()
        let pageRequestedAtEnd = gate.begin()
        gate.invalidate() // pause, previous, seek, interruption, or route loss
        XCTAssertFalse(gate.consume(pageRequestedAtEnd))
        XCTAssertNil(gate.pendingID)

        let laterExplicitNext = gate.begin()
        XCTAssertFalse(gate.consume(pageRequestedAtEnd))
        XCTAssertEqual(gate.pendingID, laterExplicitNext)
        XCTAssertTrue(gate.consume(laterExplicitNext))
        XCTAssertNil(gate.pendingID)
    }
}
