import XCTest

/// Phase 4: defusion (all five techniques), values, committed action.
final class Phase4ACTTests: SkillsUITestCase {

    func testDefusionAllTechniquesThenCommittedActionWithMiniValues() {
        launch()
        startFromToolkit(method: "ACT", tool: "Defusion")
        type("I'm not good enough", into: "The thought…")
        next()
        slide("How hooked", to: 0.8)
        next()

        tap("“I'm having the thought that")
        tap("Start")
        tap("Add “I'm having the thought that…”")
        tap("Add “I notice…”")
        expectText("I notice I'm having the thought that i'm not good enough")

        tap("Try another technique")
        tap("Name the story")
        tap("Start")
        type("not good enough", into: "The … story")
        expectText("story again")

        tap("Try another technique")
        tap("Leaves on a stream")
        tap("Start")
        type("I have too much to do", into: "A thought…")
        tap("Place")
        XCTAssertEqual(app.otherElements["Stream"].value as? String, "1 leaves floating")

        tap("Try another technique")
        tap("Thank your mind")
        tap("Start")
        tap("Thank your mind")
        expectText("Noticed.")

        tap("Try another technique")
        tap("Silly voice")
        tap("Start")
        tap("Repeat it quickly")
        expectText("Just words.", timeout: 8)
        tap("Done with this")

        slide("How hooked now", to: 0.3)
        next()
        type("Being a good friend", into: "What matters to me is…")
        dismissKeyboard()
        tap("Finish")
        expectText("You unhooked a little")
        expectText("How hooked")
        expectText("The not good enough story")

        tap("Take a small step")
        // No values yet: a quick, one-area clarification.
        expectText("Pick one area of life that matters to you.")
        tap("Friends & social")
        tap("kind")
        tap("Importance: 8 out of 10")
        next()
        type("Text Sam to ask how the move went", into: "I'll…")
        next()
        type("They'll think it's weird after so long", into: "My mind might say…")
        tap("Let me pick a smaller step")
        tap("Pick a smaller step")
        expectText("What's one small action")
        next()
        tap("Yes")
        next()
        tap("Now")
        tap("Start now")
        tap("I'm back")
        tap("Yes")
        type("Good. Awkward for a second, then fine.", into: "It felt…")
        dismissKeyboard()
        tap("Finish")
        expectText("You acted on friends & social")
    }

    func testValuesClarificationThenWeeklyCheckIn() {
        launch()
        startFromToolkit(method: "ACT", tool: "Values Check-in")
        expectText("Which parts of life matter to you?")
        tap("Spirituality & meaning")   // hide one
        next()
        expectText("What kind of person do you want to be in each?")
        tap("Work & career")
        tap("curious")
        tap("honest")
        tap("Importance: 9 out of 10")
        tap("Consistency: 3 out of 10")
        app.navigationBars["Work & career"].exists ? tap("Save") : XCTFail("Editor didn't open")
        expectText("Importance 9/10")
        tap("Save")
        expectText("Values checked in")
        expectText("Work & career")
        tap("Done")

        // Ongoing check-in re-rates consistency.
        startFromToolkit(method: "ACT", tool: "Values Check-in")
        expectText("How consistently have you acted on each lately?")
        slide("Work & career: how consistently", to: 0.6)
        tap("Save")
        expectText("Values checked in")
    }
}
