import XCTest

@MainActor
final class ListenerUITests: XCTestCase {
    func testPlayerHidingPreservesPauseAndHandlesEmptyQueue() throws {
        let app = layoutApp()
        app.launch()
        XCTAssertTrue(app.buttons["artist-demo-layout-artist"].waitForExistence(timeout: 10))
        app.buttons["artist-demo-layout-artist"].tap()
        app.buttons["Play this artist only"].tap()
        app.buttons["open-player"].tap()
        app.buttons["Pause"].firstMatch.tap()
        app.buttons["player-song-options"].tap()
        app.buttons["Hide song"].tap()
        XCTAssertTrue(app.staticTexts["Layout track 02"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Play"].firstMatch.exists, "Hiding a paused current song must not start playback")
        XCTAssertFalse(app.buttons["Pause"].exists)
        app.buttons["Minimize player"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let listen = app.scrollViews["listen-scroll"]
        let single = app.buttons["play-track-layout-track-02"]
        for _ in 0..<4 { if single.isHittable { break }; listen.swipeUp() }
        single.tap()
        app.buttons["open-player"].tap()
        app.buttons["player-song-options"].tap()
        app.buttons["Hide song"].tap()
        let empty = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.otherElements["mini-player"])
        XCTAssertEqual(XCTWaiter.wait(for: [empty], timeout: 5), .completed)
        XCTAssertTrue(app.tabBars.buttons["Settings"].isHittable, "Hiding the sole queued song must close the player")
        XCTAssertFalse(single.exists)
        XCTAssertTrue(app.buttons["play-track-layout-track-03"].exists, "Other songs by the same artist must remain available")
    }

    func testHideOneSongPersistsAndUnhideRestoresLibrary() throws {
        let app = layoutApp()
        app.launch()
        let artist = app.buttons["artist-demo-layout-artist"]
        XCTAssertTrue(artist.waitForExistence(timeout: 10))
        artist.tap()
        let playArtist = app.buttons["Play this artist only"]
        XCTAssertTrue(playArtist.waitForExistence(timeout: 5))
        playArtist.tap()
        let artistScroll = app.scrollViews["artist-scroll"]
        let options = artistScroll.buttons["Song options"].firstMatch
        for _ in 0..<4 { if options.isHittable { break }; artistScroll.swipeUp() }
        options.tap()
        let hide = app.buttons["Hide song"]
        guard hide.waitForExistence(timeout: 3) else { XCTFail("A song needs its own Hide song action"); return }
        hide.tap()
        let first = app.buttons["play-track-layout-track-01"]
        XCTAssertFalse(first.exists)
        let mini = app.otherElements["mini-player"]
        XCTAssertTrue(mini.staticTexts["Layout track 02"].waitForExistence(timeout: 5), "Hiding the current song must keep the artist's next song available")
        XCTAssertTrue(mini.buttons["Pause"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["artist-demo-layout-artist"].waitForExistence(timeout: 10))
        XCTAssertFalse(first.exists, "Hidden songs must remain hidden after relaunch")
        app.tabBars.buttons["Library"].tap()
        app.buttons["favorites-link"].tap()
        XCTAssertFalse(first.exists)
        XCTAssertTrue(app.buttons["play-track-layout-track-02"].exists)
        app.tabBars.buttons["Settings"].tap()
        let settings = app.scrollViews["settings-scroll"]
        let hiddenSongs = app.buttons["hidden-songs-link"]
        for _ in 0..<8 { if hiddenSongs.isHittable { break }; settings.swipeUp() }
        XCTAssertTrue(hiddenSongs.isHittable)
        hiddenSongs.tap()
        let unhide = app.buttons["unhide-track-layout-track-01"]
        XCTAssertTrue(unhide.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Hidden song with restore action"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        unhide.tap()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5), "Unhide must restore saved Favorites membership")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["playlist-layout-playlist-01"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5), "Unhide must restore saved playlist membership")
    }

    func testPaginationControlsRemainAboveMiniPlayer() throws {
        let app = layoutApp()
        app.launch()
        let play = app.buttons["play-track-layout-track-01"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        let mini = app.otherElements["mini-player"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        let listen = app.scrollViews["listen-scroll"]
        let catalogMore = app.buttons["catalog-show-more"]
        scrollToBottom(catalogMore, in: listen, above: mini)
        assertReachable(catalogMore, scroll: listen, above: mini, name: "Listen pagination")
        catalogMore.tap()
        XCTAssertTrue(app.buttons["play-track-layout-track-14"].waitForExistence(timeout: 5))
        XCTAssertFalse(catalogMore.exists)
        for _ in 0..<6 { listen.swipeDown(velocity: .fast) }
        let author = app.buttons["artist-demo-layout-artist"]
        XCTAssertTrue(author.isHittable)
        author.tap()
        let artist = app.scrollViews["artist-scroll"]
        let artistMore = app.buttons["artist-show-more"]
        XCTAssertTrue(artistMore.waitForExistence(timeout: 5))
        scrollToBottom(artistMore, in: artist, above: mini)
        assertReachable(artistMore, scroll: artist, above: mini, name: "Artist pagination")
        artistMore.tap()
        XCTAssertTrue(app.buttons["play-track-layout-track-14"].waitForExistence(timeout: 5))
        XCTAssertFalse(artistMore.exists)
        XCTAssertTrue(app.tabBars.buttons["Library"].isHittable)
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.scrollViews["library-scroll"].exists)
    }

    func testLibraryLastRowsRemainReachableWithMiniPlayerAtLargeTextSize() throws {
        let app = layoutApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let play = app.buttons["play-track-layout-track-01"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        let mini = app.otherElements["mini-player"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        app.tabBars.buttons["Library"].tap()
        let library = app.scrollViews["library-scroll"]
        let lastPlaylist = app.buttons["playlist-layout-playlist-08"]
        scrollToBottom(lastPlaylist, in: library, above: mini)
        assertReachable(lastPlaylist, scroll: library, above: mini, name: "Library last playlist")
        lastPlaylist.tap()
        let playlist = app.collectionViews["playlist-list"]
        let lastTrack = app.buttons["play-track-layout-track-12"]
        scrollToBottom(lastTrack, in: playlist, above: mini)
        assertReachable(lastTrack, scroll: playlist, above: mini, name: "Playlist last track")
        lastTrack.tap()
        XCTAssertTrue(app.buttons["open-player"].isHittable)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<8 { library.swipeDown(velocity: .fast) }
        app.buttons["favorites-link"].tap()
        let favorites = app.scrollViews["favorites-scroll"]
        scrollToBottom(lastTrack, in: favorites, above: mini)
        assertReachable(lastTrack, scroll: favorites, above: mini, name: "Favorites last track")
        XCTAssertTrue(app.tabBars.buttons["Settings"].isHittable)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Sign in with Meteor Wallet"].waitForExistence(timeout: 5))
    }

    private func layoutApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-layout", "--ui-test-store", UUID().uuidString,
                               "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        return app
    }

    private func scrollToBottom(_ target: XCUIElement, in scroll: XCUIElement, above mini: XCUIElement) {
        for _ in 0..<16 {
            if target.exists && target.isHittable && target.frame.maxY <= mini.frame.minY { return }
            scroll.swipeUp(velocity: .fast)
        }
    }

    private func assertReachable(_ target: XCUIElement, scroll: XCUIElement, above mini: XCUIElement, name: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(target.isHittable, "\(name) must be tappable", file: file, line: line)
        XCTAssertLessThanOrEqual(target.frame.maxY, mini.frame.minY, "\(name) must be fully above the mini player", file: file, line: line)
        // Accessibility coordinates can differ by a floating-point rounding fraction.
        XCTAssertLessThanOrEqual(scroll.frame.maxY, mini.frame.minY + 0.5, "\(name) scroll viewport must reserve the mini player's actual height", file: file, line: line)
    }

    func testMeteorOpensLiveWallet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString]
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        let meteor = app.buttons["Sign in with Meteor Wallet"]
        XCTAssertTrue(meteor.waitForExistence(timeout: 10))
        meteor.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let consent = springboard.buttons["Continue"]
        if consent.waitForExistence(timeout: 5) { consent.tap() }
        let browser = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
        let prepare = browser.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Prepare Meteor Wallet")).firstMatch
        if !prepare.waitForExistence(timeout: 30) {
            print("AUTH_APP_TREE", app.debugDescription)
            print("AUTH_BROWSER_TREE", browser.debugDescription)
            print("AUTH_SYSTEM_TREE", springboard.debugDescription)
            XCTFail("Published bridge must open inside native authentication session")
            return
        }
        prepare.tap()
        let confirm = browser.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Confirm in Meteor")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 20))
        confirm.tap()
        let walletEntry = browser.buttons["Get Started with Meteor Wallet"]
        XCTAssertTrue(walletEntry.waitForExistence(timeout: 25), "Clean simulator must reach the real Meteor wallet entry screen")
        XCTAssertTrue(browser.staticTexts["No Meteor Wallet account found for connecting to external app"].exists)
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Live Meteor authentication session"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testLiveCatalogPlaybackAndMeteorEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString]
        app.launch()
        let favorite = app.buttons["Add to favorites"].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 35), "Live public catalog must load without demo mode")
        favorite.tap()
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play ")).firstMatch
        XCTAssertTrue(play.exists)
        play.tap()
        let openPlayer = app.buttons["open-player"]
        XCTAssertTrue(openPlayer.waitForExistence(timeout: 10))
        openPlayer.tap()
        let elapsed = app.staticTexts["playback-elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        let progressed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "0:00"), object: elapsed)
        XCTAssertEqual(XCTWaiter.wait(for: [progressed], timeout: 25), .completed, "Actual remote audio time must advance")
        app.buttons["Pause"].firstMatch.tap()
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Live catalog audio playback"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["Minimize player"].tap()
        app.tabBars.buttons["Settings"].tap()
        let meteor = app.buttons["Sign in with Meteor Wallet"]
        XCTAssertTrue(meteor.waitForExistence(timeout: 5))
        XCTAssertTrue(meteor.isEnabled, "Published wallet bridge must be configured")
        XCTAssertFalse(app.buttons["Sign in with Apple"].exists, "Unavailable login must not appear usable")
    }

    func testGuestLibraryPersistsAndAuthorPlayerOpens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-test-store", UUID().uuidString]
        app.launch()
        let favorite = app.buttons["Add to favorites"].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 15))
        favorite.tap()
        XCTAssertTrue(app.buttons["Remove from favorites"].firstMatch.exists)

        app.tabBars.buttons["Library"].tap()
        app.buttons["Create playlist"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Вечер")
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Вечер"].waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Remove from favorites"].firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Вечер"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Listen"].tap()
        let author = app.buttons["artist-demo-artist"]
        XCTAssertTrue(author.waitForExistence(timeout: 5))
        author.tap()
        let authorPlay = app.buttons["Play this artist only"]
        XCTAssertTrue(authorPlay.waitForExistence(timeout: 5))
        authorPlay.tap()
        XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Artist playback"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Your music"].waitForExistence(timeout: 5), "Mini player must not cover the tab bar")
    }
}
