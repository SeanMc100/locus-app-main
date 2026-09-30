import XCTest

/// Phase 1: entry point, safety screen, method picker, triage.
final class Phase1FoundationTests: SkillsUITestCase {

    func testSavingIsOneTapAndWorkThroughIsOffered() {
        launch()
        saveEntry("Work was rough today. The presentation will go badly.")
        XCTAssertTrue(button("Work through this").exists)
        tap("Done")
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 3))
    }

    func testRiskInEntryShowsSafetyScreenBeforeAnyWork() {
        launch()
        saveEntry("Everything is falling apart and everyone would be better off without me")
        tap("Work through this")
        expectText("It sounds like things might be really hard right now.")
        XCTAssertTrue(app.links["Call 988"].exists || app.buttons["Call 988"].exists)
        expectText("Text HOME to 741741")
        expectText("If you're in immediate danger, call 911.")
        // Never blocked: Continue leads on, with crisis skills suggested first.
        tap("Continue")
        expectText("Suggested right now")
        expectText("Crisis Skills")
    }

    func testRiskTypedMidFlowShowsSafetyScreenThenContinues() {
        launch()
        startFromToolkit(method: "CBT", tool: "Thought Record")
        type("I want to kill myself", into: "Where were you, and what happened?")
        next()
        expectText("It sounds like things might be really hard right now.")
        tap("Continue")
        expectText("What did you feel?")
    }

    func testTriageRoutesHighIntensityToCrisisSkillsThenThoughtTool() {
        launch()
        openToolkit()
        tap("Work through something")
        tap("Help me choose")
        tap("Intensity: 8 out of 10")
        next()
        tap("A loop I keep going around")
        next()
        expectText("Crisis Skills")
        expectText("Afterwards, you can carry on with Defusion")
        tap("Choose something else")
        expectText("How do you want to work through this?")
    }

    func testTriageRoutesUnsureToCheckTheFacts() {
        launch()
        openToolkit()
        tap("Work through something")
        tap("Help me choose")
        tap("Intensity: 3 out of 10")
        next()
        tap("I'm not sure, I just feel bad")
        next()
        expectText("Check the Facts")
        expectText("naming the emotion")
    }

    func testSafetyPlanIsReachableAndSaves() {
        launch()
        openToolkit()
        tap("Safety plan")
        type("Not sleeping", into: "My warning signs")
        app.navigationBars["Safety plan"].buttons["Done"].tap()
        tap("Safety plan")
        let field = self.field("My warning signs")
        XCTAssertEqual(field.value as? String, "Not sleeping")
    }
}
