//
//  SparkForDOOHUITests.swift
//  SparkForDOOHUITests
//
//  Created by Muqeem Ahmad on 09/12/25.
//

import XCTest

final class SparkForDOOHUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// Verifies the basic activation flow:
    /// 1. App launches into Activation screen.
    /// 2. After the configured activation delay, the Ad player view becomes visible.
    @MainActor
    func testActivationToPlayerTransition() throws {
        let app = XCUIApplication()
        app.launch()

        // Step 1: Activation screen should appear.
        XCTAssertTrue(
            app.staticTexts["Activate your TV screen"].waitForExistence(timeout: 5),
            "Activation title should be visible on launch"
        )

        // Step 2: After the activation delay, the Ad player root view should appear.
        // Default delay is 10s (AppConfig.activationTestTransitionDelay), so we wait a bit longer.
        let player = app.otherElements["AdPlayerRootView"]
        XCTAssertTrue(
            player.waitForExistence(timeout: 20),
            "Ad player should appear after activation delay"
        )
    }
}
