import XCTest
@testable import NearFMCore

final class PlaybackQueueTests: XCTestCase {
    private func track(_ id: String, artist: String = "a") -> Track {
        Track(id: id, title: id, artistID: artist, artistName: artist,
              audioURL: URL(string: "https://example.org/\(id).mp3")!, artworkURL: nil, duration: nil)
    }

    func testReplaceAndAppendStayWithinSelectedArtistAndDeduplicate() {
        var queue = PlaybackQueue()
        queue.replace(with: [track("a1"), track("b1", artist: "b"), track("a1"), track("a2")], artistID: "a", startID: "a2")
        XCTAssertEqual(queue.tracks.map(\.id), ["a1", "a2"])
        XCTAssertEqual(queue.index, 1)
        XCTAssertEqual(queue.current?.id, "a2")
        queue.append([track("a2"), track("b2", artist: "b"), track("a3")])
        XCTAssertEqual(queue.tracks.map(\.id), ["a1", "a2", "a3"])
        XCTAssertTrue(queue.next(repeatAll: false))
        XCTAssertEqual(queue.current?.id, "a3")
        XCTAssertFalse(queue.next(repeatAll: false))
        XCTAssertEqual(queue.current?.id, "a3")
        XCTAssertTrue(queue.next(repeatAll: true))
        XCTAssertEqual(queue.current?.id, "a1")
    }

    func testEmptyQueueAndRemovalOfCurrentAuthor() {
        var queue = PlaybackQueue()
        XCTAssertNil(queue.current)
        XCTAssertEqual(queue.index, 0)
        XCTAssertFalse(queue.next(repeatAll: true))
        XCTAssertFalse(queue.previous())
        queue.replace(with: [track("a1"), track("a2")], artistID: "a", startID: "a2")
        queue.removeArtist("a")
        XCTAssertTrue(queue.tracks.isEmpty)
        XCTAssertNil(queue.current)
        XCTAssertNil(queue.artistID)
        XCTAssertEqual(queue.index, 0)
    }

    func testShuffleKeepsCurrentTrackAndAuthorScope() {
        var queue = PlaybackQueue()
        queue.replace(with: [track("a1"), track("a2"), track("a3"), track("b1", artist: "b")], artistID: "a", startID: "a2")
        queue.shuffle()
        XCTAssertEqual(queue.current?.id, "a2")
        XCTAssertEqual(Set(queue.tracks.map(\.id)), Set(["a1", "a2", "a3"]))
        XCTAssertTrue(queue.tracks.allSatisfy { $0.artistID == "a" })
    }

    func testExplicitMixedPlaylistPreservesOrderAndRemovesBlockedArtist() {
        var queue = PlaybackQueue()
        queue.replace(with: [track("a1"), track("b1", artist: "b"), track("a2")], artistID: nil, startID: "b1")
        XCTAssertNil(queue.artistID)
        XCTAssertEqual(queue.current?.id, "b1")
        queue.append([track("b1", artist: "b"), track("c1", artist: "c")])
        XCTAssertEqual(queue.tracks.map(\.id), ["a1", "b1", "a2", "c1"])
        queue.removeArtist("b")
        XCTAssertEqual(queue.tracks.map(\.id), ["a1", "a2", "c1"])
        XCTAssertNotEqual(queue.current?.artistID, "b")
    }

    func testAuthorPageBoundaryAdvancesOnlyAfterAdditionalAuthorTracksArrive() {
        var queue = PlaybackQueue()
        queue.replace(with: [track("a1")], artistID: "a")
        XCTAssertFalse(queue.next(repeatAll: false))
        XCTAssertEqual(queue.current?.id, "a1")
        queue.append([track("b1", artist: "b"), track("a2")])
        XCTAssertTrue(queue.next(repeatAll: false))
        XCTAssertEqual(queue.current?.id, "a2")
        XCTAssertFalse(queue.next(repeatAll: false))
        XCTAssertTrue(queue.next(repeatAll: true))
        XCTAssertEqual(queue.current?.id, "a1")
    }
}
