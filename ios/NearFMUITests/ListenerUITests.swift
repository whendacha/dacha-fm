import XCTest

@MainActor
final class ListenerUITests: XCTestCase {
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
