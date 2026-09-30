import XCTest

/// Phase 5: quick capture, inbox, entry ↔ session links.
final class Phase5CaptureTests: SkillsUITestCase {

    func testQuickCaptureGoesToInboxAndIsWorkedThrough() {
        launch()
        openToolkit()
        tap("Quick capture")
        type("They think I'm not good enough", into: "What's the thought?")
        tap("Shame / Guilt")
        tap("inadequate")
        tap("How strong: 5 out of 10")
        tap("Work")
        tap("Save to inbox")
        expectText("Saved to your inbox")
        tap("Done")
        expectText("Thoughts to work through")
        expectText("They think I'm not good enough")
        tap("Work through this")
        expectText("How do you want to work through this?")
        expectText("They think I'm not good enough")
        tap("CBT")
        tap("Thought Record")
        expectText("What was happening?")
        // Discarding puts the thought back in the inbox.
        tap("Close")
        tap("Discard")
        expectText("Thoughts to work through")
    }

    func testStrongCaptureOffersCalmingSkill() {
        launch()
        openToolkit()
        tap("Quick capture")
        type("Everything is going wrong", into: "What's the thought?")
        tap("How strong: 9 out of 10")
        tap("Save to inbox")
        expectText("That's a strong feeling")
        tap("Try a calming skill")
        expectText("How intense is it right now?", timeout: 6)
    }

    func testArchivedCaptureLeavesInbox() {
        launch()
        openToolkit()
        tap("Quick capture")
        type("I should have said something", into: "What's the thought?")
        tap("Save to inbox")
        tap("Done")
        expectText("I should have said something")
        tap("Archive")
        expectNoText("Thoughts to work through")
    }

    func testEntryAndSessionLinkBothWays() {
        launch()
        saveEntry("Rough evening. I can't handle this.")
        tap("Work through this")
        tap("DBT")
        tap("Crisis Skills")
        tap("Intensity: 6 out of 10")
        next()
        tap("STOP")
        next(); next(); next()
        tap("Skip")
        type("Make tea and sit down", into: "What I'll do…")
        next()
        tap("Intensity now: 3 out of 10")
        tap("Finish")
        tap("Done")
        // Entry -> session.
        tap("History")
        app.cells.firstMatch.tap()
        expectText("Worked through with")
        tap("Crisis Skills")
        expectText("Make tea and sit down")
        // Session -> entry.
        tap("From your journal entry")
        expectText("Rough evening.")
    }

    func testPastEntryCanBeWorkedThroughFromHistory() {
        launch()
        saveEntry("Another day, another deadline.")
        tap("Done")
        tap("History")
        app.cells.firstMatch.tap()
        app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", "More")).firstMatch.tap()
        tap("Work through this")
        expectText("How do you want to work through this?")
    }
}

/// Phase 6: insights.
final class Phase6InsightsTests: SkillsUITestCase {

    private func openInsights() {
        openToolkit()
        tap("Insights")
        expectText("Computed on this device")
    }

    func testEmptyStatesExplainWhatWillAppear() {
        launch()
        openInsights()
        tap("Belief Ledger")
        expectText("No beliefs tracked yet")
        app.navigationBars.buttons.firstMatch.tap()
        tap("Prediction Calibration")
        expectText("0 of 5 predictions recorded")
        app.navigationBars.buttons.firstMatch.tap()
        tap("Patterns")
        expectText("Patterns appear as you go")
        app.navigationBars.buttons.firstMatch.tap()
        tap("Values Gap")
        expectText("No values clarified yet")
        app.navigationBars.buttons.firstMatch.tap()
        tap("Practice")
        expectText("No cards yet")
    }

    func testInsightsComputeFromRecords() {
        launch(extra: ["-seedSkillsDemo"])
        openInsights()
        tap("Belief Ledger")
        expectText("I'm falling behind")
        expectText("Loosening")
        tap("“I'm falling behind”")
        expectText("Strength over time")
        expectText("Shipped the project on time.")
        expectText("I'm behind on one thing, not everything.")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()

        tap("Prediction Calibration")
        // (0 + 0.5 + 0 + 1 + 0) / 5 = 30%; estimates average 77%.
        expectText("came true 30% of the time. You estimated 77% on average.")
        expectText("as bad as you expected")
        app.navigationBars.buttons.firstMatch.tap()

        tap("Patterns")
        expectText("Most frequent emotions")
        expectText("Which skills help you most")
        expectText("Poor sleep appeared in 2 of 2 chains.")
        expectText("Walk for 10 minutes")
    }

    func testIfThenPlanRecordsHitRate() {
        launch()
        openInsights()
        tap("Practice")
        tap("New if-then plan")
        type("I start doomscrolling after 11pm", into: "If…")
        type("put the phone in the kitchen", into: "then I'll…")
        tap("Save plan")
        expectText("If I start doomscrolling after 11pm, then I'll put the phone in the kitchen.")
        tap("It fired")
        expectText("fired 100% of 1 time")
    }

    func testExportShowsContentsAndMakesFiles() {
        launch(extra: ["-seedSkillsDemo"])
        openInsights()
        tap("Export")
        expectText("Will include:")
        tap("Create PDF")
        tap("Create JSON backup")
        expectText(".pdf")
        expectText(".json")
    }
}

/// Phase 7: AI toggle and fallbacks. The Simulator can't run the on-device
/// model, which is exactly the "AI on but unavailable" path.
final class Phase7AITests: SkillsUITestCase {

    func testAIToggleExplainsAndFlowsFallBackToQuestionBank() {
        launch()
        openToolkit()
        tap("Settings")
        expectText("nothing is sent anywhere")
        let toggle = app.switches["Use AI in the skills toolkit"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        if (toggle.value as? String) == "0" { toggle.switches.firstMatch.tap() }
        tap("Done")
        tap("Work through something")
        tap("CBT")
        tap("Thought Record")
        // The offline question bank still works.
        expectText("If a camera had filmed it, what would it show?")
    }

    func testSafetyScreenStillShowsWithAIOn() {
        launch(extra: ["-skills.ai.enabled", "YES"])
        saveEntry("I don't want to be alive anymore")
        tap("Work through this")
        expectText("It sounds like things might be really hard right now.")
    }
}
