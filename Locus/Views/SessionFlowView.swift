import SwiftUI
import SwiftData

/// Runs the post-journal flow for one entry, depending on `flow`:
/// - question: one AI-chosen question -> written answer -> summary
/// - judgement: rate -> stripped version + re-rate -> optional friend
///   reply / truer judgement -> summary
/// - sort: extraction -> review -> sort -> counterpart -> summary
struct SessionFlowView: View {
    enum Flow { case question, judgement, sort }

    /// Testing (2026-09-26): the question flow is the default. The other
    /// two are kept intact; switch back here.
    static let flow: Flow = .question

    let text: String
    /// Called as soon as the entry is saved to history (before the summary
    /// is dismissed), so the draft is cleared even if the app is killed on
    /// the summary screen.
    let onSaved: () -> Void
    /// Called when the flow should close (cancelled or done).
    let onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext

    private enum Step {
        case findingQuestion
        case question(QuestionAsker.Asked)
        case rateBefore
        case findingJudgements
        case judgements
        case ownWords
        case analyzing
        case failed(String)
        case review
        case sorting
        case counterpart(inControl: [String], notInControl: [String])
        case summary(JournalEntry)
    }

    @State private var step: Step = Self.firstStep

    private static var firstStep: Step {
        switch flow {
        case .question: .findingQuestion
        case .judgement: .rateBefore
        case .sort: .analyzing
        }
    }
    @State private var items: [ExtractedItem] = []
    /// Quotes found by `JudgementFinder`, highlighted downstream and saved.
    @State private var judgementQuotes: [String] = []
    /// The entry rewritten with those judgements removed; saved.
    @State private var withoutJudgements = ""
    /// Finding runs in the background while the user rates, so it's
    /// tracked apart from `step`.
    @State private var findingDone = false
    @State private var findingError: String?
    @State private var intensityBefore: Int?
    @State private var intensityAfter: Int?
    var body: some View {
        NavigationStack {
            content
                .background(Color.white)
                .animation(.easeInOut(duration: 0.25), value: stepID)
        }
        .task {
            switch Self.flow {
            case .question: await findQuestion()
            case .judgement: await findJudgements()
            case .sort: await analyze()
            }
        }
    }

    private var stepID: Int {
        switch step {
        case .findingQuestion: 10
        case .question: 11
        case .rateBefore: 9
        case .findingJudgements: 7
        case .judgements: 8
        case .ownWords: 6
        case .analyzing: 0
        case .failed: 1
        case .review: 2
        case .sorting: 3
        case .counterpart: 4
        case .summary: 5
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .findingQuestion:
            AnalyzingView(title: "Reading your entry",
                          subtitle: "Finding a question for you.\nEverything stays on this device.") { onFinish() }
        case .question(let asked):
            QuestionView(entryText: text,
                         asked: asked,
                         onCancel: { onFinish() },
                         onFinish: { saveQuestionFlow(asked, answer: $0) })
        case .rateBefore:
            RateBeforeView(onCancel: { onFinish() }) { rating in
                intensityBefore = rating
                step = .findingJudgements
                showJudgementsIfFound()
            }
        case .findingJudgements:
            AnalyzingView(title: "Reading your entry",
                          subtitle: "Finding the judgements you added.\nThis takes a few seconds.\nEverything stays on this device.") { onFinish() }
        case .judgements:
            JudgementsView(entryText: text,
                           judgements: judgementQuotes,
                           withoutJudgements: withoutJudgements,
                           ratingBefore: intensityBefore,
                           initialRatingAfter: intensityAfter,
                           onCancel: { onFinish() },
                           onContinue: { rating in
                               intensityAfter = rating
                               step = .ownWords
                           })
        case .ownWords:
            OwnWordsView(entryText: text,
                         highlights: judgementQuotes,
                         onBack: {
                             if findingError == nil { step = .judgements } else { onFinish() }
                         },
                         onComplete: saveJudgementFlow)
        case .analyzing:
            AnalyzingView(title: "Reading your entry",
                          subtitle: "Pulling out the things on your mind.\nEverything stays on this device.") { onFinish() }
        case .failed(let message):
            switch Self.flow {
            case .question:
                FailedView(title: "Couldn't find a question",
                           message: message,
                           manualTitle: "Use a general question",
                           onRetry: { Task { await findQuestion() } },
                           onManual: { step = .question(QuestionAsker.noFit(notes: "AI failed: \(message)")) },
                           onCancel: { onFinish() })
            case .judgement:
                FailedView(title: "Couldn't find judgements",
                           message: message,
                           manualTitle: "Skip to the next step",
                           onRetry: {
                               step = .findingJudgements
                               Task { await findJudgements() }
                           },
                           onManual: { step = .ownWords },
                           onCancel: { onFinish() })
            case .sort:
                FailedView(title: "Couldn't break it down",
                           message: message,
                           manualTitle: "Add items by hand",
                           onRetry: { Task { await analyze() } },
                           onManual: { step = .review },
                           onCancel: { onFinish() })
            }
        case .review:
            ReviewItemsView(items: $items,
                            onCancel: { onFinish() },
                            onContinue: { step = .sorting })
        case .sorting:
            SortCardsView(items: items.map(\.text),
                          onBack: { step = .review },
                          onComplete: proceedToCounterpart)
        case .counterpart(let inControl, let notInControl):
            CounterpartView(items: notInControl) { counterparts in
                save(inControl: inControl, notInControl: notInControl, counterparts: counterparts)
            }
        case .summary(let entry):
            SummaryView(entry: entry) { onFinish() }
        }
    }

    private func findQuestion() async {
        step = .findingQuestion
        #if DEBUG
        // The Simulator can't run Foundation Models. Launch with
        // `-sampleQuestion` to exercise the flow's UI with canned output.
        if ProcessInfo.processInfo.arguments.contains("-sampleQuestion") {
            try? await Task.sleep(for: .seconds(2))
            step = .question(QuestionAsker.Asked(
                question: "If a friend told you “Everyone else seems to have it figured out and I’m just falling further behind”, what would you say back?",
                moveID: "friend",
                notes: "disappointment · friend · crux “Everyone else seems to have it figured out and I’m just falling further behind” (sample)"))
            return
        }
        #endif
        // Recent sessions' moves and questions, newest first, so the same
        // question doesn't come round again too soon.
        var recent = FetchDescriptor<JournalEntry>(predicate: #Predicate { !$0.questionMove.isEmpty },
                                                   sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        recent.fetchLimit = 6
        let entries = (try? modelContext.fetch(recent)) ?? []
        do {
            let asked = try await QuestionAsker.ask(about: text,
                                                    recentMoves: entries.map(\.questionMove),
                                                    recentQuestions: entries.map(\.question))
            step = .question(asked)
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    private func saveQuestionFlow(_ asked: QuestionAsker.Asked, answer: String) {
        let entry = JournalEntry(text: text,
                                 question: asked.question,
                                 questionAnswer: answer,
                                 questionMove: asked.moveID,
                                 questionNotes: asked.notes)
        modelContext.insert(entry)
        try? modelContext.save()
        onSaved()
        step = .summary(entry)
    }

    /// Runs in the background from the start (usually while the user is
    /// on the rating step), then advances only if they're waiting on it.
    private func findJudgements() async {
        findingDone = false
        findingError = nil
        #if DEBUG
        // The Simulator can't run Foundation Models. Launch with
        // `-sampleJudgements` to exercise the flow's UI with real output
        // captured from the Mac harness (only matches that sample entry).
        if ProcessInfo.processInfo.arguments.contains("-sampleJudgements") {
            try? await Task.sleep(for: .seconds(2))
            judgementQuotes = ["Life sucks today", "proof nobody will ever want to be with me",
                               "Everyone else seems to have it figured out and I’m just falling further behind",
                               "loser", "She probably thought I was weird", "I should be married by now"]
            withoutJudgements = "I got turned down again. I went home and ate dinner, and I feel tired."
            findingDone = true
            showJudgementsIfFound()
            return
        }
        #endif
        do {
            let found = try await JudgementFinder.find(in: text)
            let stripped = await JudgementFinder.withoutJudgements(text, quotes: found)
            judgementQuotes = found
            withoutJudgements = stripped
        } catch {
            findingError = error.localizedDescription
        }
        findingDone = true
        showJudgementsIfFound()
    }

    private func showJudgementsIfFound() {
        guard case .findingJudgements = step, findingDone else { return }
        if let findingError {
            step = .failed(findingError)
        } else {
            step = .judgements
        }
    }

    private func analyze() async {
        step = .analyzing
        do {
            let extracted = try await ItemExtractor.extract(from: text)
            items = extracted.map { ExtractedItem(text: $0) }
            step = .review
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    private func proceedToCounterpart(inControl: [String], notInControl: [String]) {
        if notInControl.isEmpty {
            save(inControl: inControl, notInControl: notInControl, counterparts: [])
        } else {
            step = .counterpart(inControl: inControl, notInControl: notInControl)
        }
    }

    private func saveJudgementFlow(_ mode: OwnWordsView.Mode, _ words: String) {
        let entry = JournalEntry(text: text,
                                 friendReply: mode == .friend ? words : "",
                                 judgements: judgementQuotes,
                                 withoutJudgements: withoutJudgements,
                                 intensityBefore: intensityBefore,
                                 intensityAfter: intensityAfter,
                                 truerJudgement: mode == .truer ? words : "")
        modelContext.insert(entry)
        try? modelContext.save()
        onSaved()
        step = .summary(entry)
    }

    private func save(inControl: [String], notInControl: [String], counterparts: [String]) {
        let entry = JournalEntry(text: text,
                                  inControl: inControl,
                                  notInControl: notInControl,
                                  counterparts: counterparts)
        modelContext.insert(entry)
        try? modelContext.save()
        onSaved()
        step = .summary(entry)
    }
}

private struct AnalyzingView: View {
    let title: String
    let subtitle: String
    let onCancel: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .light))
                .symbolEffect(.pulse, options: .repeating)
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.black.opacity(0.5))
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}

private struct FailedView: View {
    let title: String
    let message: String
    let manualTitle: String
    let onRetry: () -> Void
    let onManual: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 34, weight: .light))
            Text(title)
                .font(.system(size: 22, weight: .semibold))
            Text(message)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(.black.opacity(0.55))
                .padding(.horizontal, 32)
            VStack(spacing: 10) {
                PrimaryButton(title: "Try again", action: onRetry)
                Button(manualTitle, action: onManual)
                    .font(.system(size: 15, weight: .medium))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}

/// Full-width black button used across the flow.
struct PrimaryButton: View {
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.25 : 1)
    }
}
