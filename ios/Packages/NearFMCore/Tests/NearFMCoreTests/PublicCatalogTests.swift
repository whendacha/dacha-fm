import XCTest
@testable import NearFMCore

final class PublicCatalogTests: XCTestCase {
    private func song(_ extra: String = "") -> String {
        """
        {"uuid":"song-1","uploader_id":32,"uploader_account_id":"tinsman.near",
        "uploader_display_name":null,"title":"Beautiful India","audio_duration_seconds":273,
        "audio_url":"https://main.fastfs.io/author/song.mp3","cover_image_url":null,
        "score":0.038892,"uploader_reputation":2.03\(extra)}
        """
    }

    func testLiveSchemaMappingIgnoresUnneededNumericFieldsAndUsesStableUploaderID() throws {
        let decoded = try JSONDecoder().decode(PublicCatalogSong.self, from: Data(song().utf8))
        let track = try XCTUnwrap(decoded.track)
        XCTAssertEqual(track.id, "song-1")
        XCTAssertEqual(track.artistID, "32")
        XCTAssertEqual(track.artistName, "tinsman.near")
        XCTAssertEqual(track.duration, 273)
        XCTAssertNil(track.artworkURL)
    }

    func testHiddenDeletedAndUnvalidatedSongsCannotBecomePlayableTracks() throws {
        for extra in [",\"is_hidden\":true", ",\"is_deleted\":true", ",\"is_validated\":false"] {
            XCTAssertNil(try JSONDecoder().decode(PublicCatalogSong.self, from: Data(song(extra).utf8)).track)
        }
    }

    func testMissingOrUnsafeAudioIsDroppedWithoutLosingOtherSongsOrPagination() throws {
        let noAudio = song().replacingOccurrences(of: "\"https://main.fastfs.io/author/song.mp3\"", with: "null")
        let json = "{\"songs\":[\(noAudio),\(song())],\"page\":1,\"limit\":2}"
        let page = try JSONDecoder().decode(PublicCatalogPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.tracks().count, 1)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.tracks(artistID: "32").count, 1)
        XCTAssertTrue(page.tracks(artistID: "3").isEmpty)
        XCTAssertNil(PublicCatalogSong.httpsURL("http://example.com/song.mp3"))
        XCTAssertNil(PublicCatalogSong.httpsURL("https://user:password@example.com/song.mp3"))
    }
}
