import XCTest

/// Shared helpers for the skills-toolkit walkthroughs. The app runs with
/// `-uiTesting` (in-memory or throwaway stores, never real data or iCloud)
/// and with the onboarding note already seen.
@MainActor
class SkillsUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// On failure, keep a screenshot and the accessibility tree.
    override func tearDown() async throws {
        if let app, (testRun?.failureCount ?? 0) > 0 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Failure screenshot"
            shot.lifetime = .keepAlways
            add(shot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Failure UI tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
    }

    /// `store`: a throwaway on-disk store name, to keep data across relaunches.
    func launch(store: String? = nil, extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skills.onboardingSeen", "YES", "-draft.text", ""] + extra
        if let store { app.launchArguments += ["-uiTestingStore", store] }
        app.launch()
    }

    // MARK: Finding things

    /// The button with this label (or, failing that, starting with it),
    /// preferring one that's hittable when a sheet leaves others behind it.
    func button(_ label: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        for predicate in [NSPredicate(format: "label == %@", label), NSPredicate(format: "label BEGINSWITH %@", label)] {
            let query = app.buttons.matching(predicate)
            if query.firstMatch.waitForExistence(timeout: 3) {
                let all = query.allElementsBoundByIndex
                return all.first(where: { $0.isHittable }) ?? all.last ?? query.firstMatch
            }
        }
        XCTFail("No button “\(label)”", file: file, line: line)
        return app.buttons[label]
    }

    func tap(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let b = button(label, file: file, line: line)
        scrollTo(b)
        b.tap()
    }

    /// Text inputs: single-line fields are textFields, multi-line are textViews.
    func field(_ label: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@ OR placeholderValue == %@", label, label)
        let deadline = Date.now.addingTimeInterval(5)
        repeat {
            for query in [app.textFields, app.textViews] {
                let e = query.matching(predicate).firstMatch
                if e.exists { return e }
            }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date.now < deadline
        XCTFail("No field “\(label)”", file: file, line: line)
        return app.textFields[label]
    }

    func type(_ text: String, into label: String, file: StaticString = #filePath, line: UInt = #line) {
        let f = field(label, file: file, line: line)
        scrollTo(f)
        f.tap()
        f.typeText(text)
    }

    func slide(_ label: String, to position: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        dismissKeyboard()
        let s = app.sliders[label]
        XCTAssertTrue(s.waitForExistence(timeout: 3), "No slider “\(label)”", file: file, line: line)
        scrollTo(s)
        let rated = NSPredicate(format: "value != %@", "Not rated yet")
        for attempt in 0..<3 {
            s.adjust(toNormalizedSliderPosition: min(1, position + CGFloat(attempt) * 0.03))
            let done = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: rated, object: s)], timeout: 1.5)
            if done == .completed { return }
        }
        XCTFail("Slider “\(label)” didn't take a value", file: file, line: line)
    }

    /// Checks specific element types; an any-element query takes ~30 s per
    /// check on chart-heavy screens.
    private func textExists(_ text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        return [app.staticTexts, app.buttons, app.otherElements, app.cells, app.textViews, app.textFields, app.links]
            .contains { $0.matching(predicate).firstMatch.exists }
    }

    func expectText(_ text: String, timeout: TimeInterval = 4, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date.now.addingTimeInterval(timeout)
        repeat {
            if textExists(text) { return }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date.now < deadline
        XCTFail("Expected “\(text)” on screen", file: file, line: line)
    }

    func expectNoText(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(textExists(text), "Didn't expect “\(text)”", file: file, line: line)
    }

    /// Uses the "Hide keyboard" button where there is one; otherwise drags
    /// in the top third of the screen, well clear of the suggestion bar
    /// (a swipe that lands on it inserts a word).
    func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        let hide = app.buttons["Hide keyboard"]
        if hide.exists && hide.isHittable {
            hide.tap()
        } else {
            // Upward, so a sheet isn't dragged closed.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        }
        let gone = NSPredicate(format: "exists == false")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: app.keyboards.firstMatch)], timeout: 2)
    }

    /// Scrolls the frontmost scroll view until the element is hittable.
    func scrollTo(_ element: XCUIElement) {
        var tries = 0
        while !element.isHittable && tries < 8 {
            dismissKeyboard()
            if element.isHittable { break }
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            tries += 1
        }
    }

    func next() { dismissKeyboard(); tap("Next") }

    // MARK: Navigation

    func openToolkit() {
        tap("Toolkit")
        expectText("Toolkit")
    }

    /// Toolkit -> Work through something -> method -> tool.
    func startFromToolkit(method: String, tool: String) {
        openToolkit()
        tap("Work through something")
        tap(method)
        tap(tool)
    }

    /// Writes and saves a journal entry (skills post-entry flow).
    func saveEntry(_ text: String) {
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(text)
        tap("Save")
        expectText("Saved to history")
    }
}
