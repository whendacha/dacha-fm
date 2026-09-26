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
    func testLegacyLibraryDecodesAndEmitsEmptyHiddenTracks() throws {
        let legacy = Data(#"{"version":4,"favorites":[],"playlists":[],"blocked_artist_ids":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: legacy)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        XCTAssertEqual(snapshot.version, 4)
        XCTAssertNotNil(object["hidden_tracks"] as? [[String: Any]], "Legacy libraries must upgrade to an explicit empty hidden-track list")
        XCTAssertEqual((object["hidden_tracks"] as? [[String: Any]])?.count, 0)
        XCTAssertNil(object["hiddenTracks"])
    }

    func testHiddenTrackWireMetadataSurvivesRoundTrip() throws {
        let data = Data(#"{"version":5,"favorites":[],"playlists":[],"blocked_artist_ids":[],"hidden_tracks":[{"id":"hidden-song","title":"Hidden song","artist_id":"author","artist_name":"Artist","audio_url":"https://example.org/hidden.mp3","artwork_url":null,"duration":180}]}"#.utf8)
        let snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        let hidden = try XCTUnwrap(object["hidden_tracks"] as? [[String: Any]])
        XCTAssertEqual(hidden.count, 1)
        XCTAssertEqual(hidden[0]["id"] as? String, "hidden-song")
        XCTAssertEqual(hidden[0]["title"] as? String, "Hidden song")
        XCTAssertEqual(hidden[0]["audio_url"] as? String, "https://example.org/hidden.mp3")
    }

}
