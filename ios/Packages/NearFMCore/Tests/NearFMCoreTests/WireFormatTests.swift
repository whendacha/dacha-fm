import XCTest
@testable import NearFMCore

final class WireFormatTests: XCTestCase {
    func testSnakeCaseCatalogDecodingAndLibraryEncoding() throws {
        let trackJSON = #"{"id":"song-uuid","title":"Title","artist_id":"artist-slug","artist_name":"Artist","audio_url":"https://example.org/audio.mp3","artwork_url":null,"duration":180.0}"#.data(using: .utf8)!
        let track = try JSONDecoder().decode(Track.self, from: trackJSON)
        XCTAssertEqual(track.artistID, "artist-slug")
        XCTAssertEqual(track.audioURL.absoluteString, "https://example.org/audio.mp3")
        let artistJSON = #"{"id":"artist-slug","name":"Artist","artwork_url":null,"track_count":1}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(Artist.self, from: artistJSON).trackCount, 1)
        let snapshot = LibrarySnapshot(version: 3, favorites: [track], playlists: [], blockedArtistIDs: ["blocked"])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        XCTAssertEqual(object["blocked_artist_ids"] as? [String], ["blocked"])
        XCTAssertNil(object["blockedArtistIDs"])
        let favorites = try XCTUnwrap(object["favorites"] as? [[String: Any]])
        XCTAssertEqual(favorites[0]["artist_id"] as? String, "artist-slug")
        XCTAssertEqual(favorites[0]["audio_url"] as? String, "https://example.org/audio.mp3")
    }
}
