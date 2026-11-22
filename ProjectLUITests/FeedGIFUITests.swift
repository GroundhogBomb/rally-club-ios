import XCTest

final class FeedGIFUITests: XCTestCase {
    @MainActor
    func testPostDisplaysGIF() {
        let app = XCUIApplication()
        app.launchArguments = ["--feed-gif-ui-test"]
        app.launch()

        let gif = app.images["clubFeed-gif"]
        XCTAssertTrue(gif.waitForExistence(timeout: 10))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "GIF in post"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
