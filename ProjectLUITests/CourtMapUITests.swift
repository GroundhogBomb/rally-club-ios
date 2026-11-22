import XCTest

final class CourtMapUITests: XCTestCase {
    @MainActor
    func testCourtMapExposesMarkerAndShowsAddressWhenSelected() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--court-map-ui-test"]
        app.launch()

        let map = app.descendants(matching: .any).matching(identifier: "court-map").firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        let marker = app.buttons["court-map-marker-Northbank Courts"]
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        marker.tap()
        XCTAssertTrue(app.staticTexts["Northbank Park"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Northbank Courts"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Court map callout"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
