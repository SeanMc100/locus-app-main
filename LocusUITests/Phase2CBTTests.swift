import XCTest

/// Phase 2: thought record, behavioral experiment, behavioral activation.
final class Phase2CBTTests: SkillsUITestCase {

    private func fillThoughtRecordThroughBelief() {
        type("At my desk after the deadline moved.", into: "Where were you, and what happened?")
        next()
        tap("Fear / Anxiety")
        tap("anxious")
        slide("How strong is anxious", to: 0.8)
        next()
        type("I'm falling behind", into: "Thought 1")
        next()
        slide("Belief in the thought", to: 0.9)
    }

    func testThoughtRecordEndToEndWithFakeReframeCheck() {
        launch()
        startFromToolkit(method: "CBT", tool: "Thought Record")
        expectText("Step 1 of 9")
        fillThoughtRecordThroughBelief()
        next()
        // Distortions are optional.
        expectText("Do any of these thinking traps fit?")
        tap("Overgeneralization")
        next()
        type("I missed one deadline.", into: "The facts that point this way…")
        next()
        type("My review was good.", into: "The facts that don't fit…")
        next()
        type("Everything is perfect.", into: "A more balanced way to see it…")
        slide("How much do you believe the balanced thought?", to: 0.2)
        next()
        // Fake-reframe check: believable, not just positive.
        expectText("A balanced thought should feel believable")
        tap("Keep it")
        expectText("Now, how much do you believe the original thought?")
        slide("Belief in the original thought", to: 0.4)
        slide("Anxious", to: 0.3)
        dismissKeyboard()
        tap("Finish")
        expectText("You examined the thought")
        expectText("Belief in the thought")
        tap("Add the balanced thought to your Practice deck")
        expectText("Added to your Practice deck")
        tap("Done")
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 3))
    }

    func testThoughtRecordResumesAfterAppIsKilled() {
        let store = "resume-\(UUID().uuidString)"
        launch(store: store)
        startFromToolkit(method: "CBT", tool: "Thought Record")
        fillThoughtRecordThroughBelief()
        tap("Close")
        tap("Save and finish later")
        app.terminate()

        launch(store: store)
        openToolkit()
        expectText("In progress")
        expectText("Step 4 of 9")
        tap("Thought Record")
        expectText("How much do you believe it right now?")
        expectNoText("Drag to rate")
        // Back keeps what was typed.
        tap("Back")
        XCTAssertEqual(field("Thought 1").value as? String, "I'm falling behind")
    }

    func testBackFromFirstStepReturnsToToolPicker() {
        launch()
        startFromToolkit(method: "CBT", tool: "Thought Record")
        tap("Back")
        expectText("Choose a tool.")
        tap("Close")
        openToolkit()
        expectNoText("In progress")
    }

    func testBehavioralExperimentScheduledThenOutcome() {
        let store = "exp-\(UUID().uuidString)"
        launch(store: store)
        startFromToolkit(method: "CBT", tool: "Behavioral Experiment")
        type("The presentation will go badly", into: "I predict that…")
        type("People look bored and nobody asks questions", into: "Something observable…")
        slide("How sure are you it will happen?", to: 0.8)
        next()
        type("It goes okay and a couple of people ask questions", into: "It could also…")
        slide("How sure are you of this one?", to: 0.3)
        next()
        type("Give the presentation without over-rehearsing", into: "I'll…")
        tap("Tomorrow")
        type("Whether people ask questions", into: "How you'll know how it went…")
        next()
        type("I start panicking", into: "If…")
        type("do paced breathing for a minute", into: "then I'll…")
        next()
        tap("Schedule it")
        expectText("Experiment planned")
        tap("Done")
        app.terminate()

        launch(store: store)
        openToolkit()
        expectText("Planned for")
        tap("Behavioral Experiment")
        expectText("What actually happened?")
        type("Two people asked questions and my manager said it was clear.", into: "What happened was…")
        tap("No")
        slide("How bad you expected it to be", to: 0.8)
        slide("How bad it actually was", to: 0.2)
        next()
        type("It went better than I predicted.", into: "I learned…")
        slide("Belief in the prediction now", to: 0.3)
        dismissKeyboard()
        tap("Finish")
        expectText("You tested it")
        expectText("prediction calibration")
    }

    func testBehavioralActivationNowThenCheckIn() {
        launch()
        startFromToolkit(method: "CBT", tool: "Behavioral Activation")
        tap("Mood: 3 out of 10")
        tap("Energy: 2 out of 10")
        next()
        tap("Walk for 10 minutes")
        next()
        tap("Now")
        tap("Start now")
        expectText("Go for it")
        tap("I'm back")
        tap("Yes")
        tap("Mastery: 5 out of 10")
        tap("Pleasure: 7 out of 10")
        tap("Mood now: 6 out of 10")
        tap("Finish")
        expectText("You did it")
        expectText("Mood")
    }
}
