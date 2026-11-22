import XCTest

final class DemoPostUITests: XCTestCase {
    @MainActor
    func testPublishingUpdatesFeedAndMe() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        // The welcome animation blocks taps for 2.85 seconds while the entry is already in the AX tree.
        try await Task.sleep(for: .seconds(3))

        let demo = app.buttons["continue-demo"]
        XCTAssertTrue(demo.wait(for: \.isHittable, toEqual: true, timeout: 10))
        demo.tap()

        let meTab = app.tabBars.buttons["Me"]
        XCTAssertTrue(meTab.waitForExistence(timeout: 10))
        meTab.tap()
        assertPostCount(1, in: app)

        app.tabBars.buttons["Feed"].tap()
        let posts = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "post-content-link-"))
        let originalFirstPost = posts.firstMatch
        XCTAssertTrue(originalFirstPost.waitForExistence(timeout: 5))
        let originalID = originalFirstPost.identifier

        app.buttons["create-post-button"].tap()
        let editor = app.textViews["post-text-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        let text = "Great rally on court two today."
        editor.typeText(text)
        app.buttons["publish-post-button"].tap()

        let newFirstPost = posts.firstMatch
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "hittable == true AND identifier != %@", originalID
        ), object: newFirstPost)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        attachScreenshot(named: "S3 feed after publish", in: app)

        newFirstPost.tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5))
        app.navigationBars.buttons["localized-back-button"].tap()

        meTab.tap()
        assertPostCount(2, in: app)
        attachScreenshot(named: "S3 profile count", in: app)
    }

    private func assertPostCount(_ count: Int, in app: XCUIApplication) {
        let metric = app.descendants(matching: .any).matching(identifier: "profile-post-count").firstMatch
        XCTAssertTrue(metric.waitForExistence(timeout: 5))
        XCTAssertEqual(metric.label.split(whereSeparator: { !$0.isNumber }).first, String(count)[...])
    }

    private func attachScreenshot(named name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
