import XCTest

@MainActor
final class ListenerUITests: XCTestCase {
    func testMeteorOpensLiveWallet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store", UUID().uuidString]
        app.launch()
        app.tabBars.buttons["Настройки"].tap()
        let meteor = app.buttons["Войти через Meteor Wallet"]
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
        let favorite = app.buttons["Добавить в избранное"].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 35), "Live public catalog must load without demo mode")
        favorite.tap()
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Слушать ")).firstMatch
        XCTAssertTrue(play.exists)
        play.tap()
        let openPlayer = app.buttons["open-player"]
        XCTAssertTrue(openPlayer.waitForExistence(timeout: 10))
        openPlayer.tap()
        let elapsed = app.staticTexts["playback-elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        let progressed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "0:00"), object: elapsed)
        XCTAssertEqual(XCTWaiter.wait(for: [progressed], timeout: 25), .completed, "Actual remote audio time must advance")
        app.buttons["Пауза"].firstMatch.tap()
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Live catalog audio playback"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["Свернуть плеер"].tap()
        app.tabBars.buttons["Настройки"].tap()
        let meteor = app.buttons["Войти через Meteor Wallet"]
        XCTAssertTrue(meteor.waitForExistence(timeout: 5))
        XCTAssertTrue(meteor.isEnabled, "Published wallet bridge must be configured")
        XCTAssertFalse(app.buttons["Войти через Apple"].exists, "Unavailable login must not appear usable")
    }

    func testGuestLibraryPersistsAndAuthorPlayerOpens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-test-store", UUID().uuidString]
        app.launch()
        let favorite = app.buttons["Добавить в избранное"].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 15))
        favorite.tap()
        XCTAssertTrue(app.buttons["Убрать из избранного"].firstMatch.exists)

        app.tabBars.buttons["Библиотека"].tap()
        app.buttons["Создать плейлист"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Вечер")
        app.alerts.buttons["Создать"].tap()
        XCTAssertTrue(app.staticTexts["Вечер"].waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Убрать из избранного"].firstMatch.waitForExistence(timeout: 10))
        app.tabBars.buttons["Библиотека"].tap()
        XCTAssertTrue(app.staticTexts["Вечер"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Слушать"].tap()
        let author = app.buttons["artist-demo-artist"]
        XCTAssertTrue(author.waitForExistence(timeout: 5))
        author.tap()
        let authorPlay = app.buttons["Слушать только этого автора"]
        XCTAssertTrue(authorPlay.waitForExistence(timeout: 5))
        authorPlay.tap()
        XCTAssertTrue(app.buttons["Пауза"].firstMatch.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Artist playback"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.tabBars.buttons["Библиотека"].tap()
        XCTAssertTrue(app.staticTexts["Ваша музыка"].waitForExistence(timeout: 5), "Mini player must not cover the tab bar")
    }
}
