import SwiftUI
import SwiftData

/// DBT crisis skills: rate intensity, then TIPP (one or more body-based
/// skills) or STOP (one screen per letter), then re-rate. If it's still
/// very high, offer another skill and the safety plan.
struct CrisisSkillsFlow: View {
    let session: TherapySession
    let callbacks: FlowCallbacks

    @Environment(\.modelContext) private var modelContext
    @Environment(\.safetyGate) private var safetyGate

    enum Step: String {
        case intensity, choose, tipp, stopS, stopT, stopO, stopP, rerate, complete
    }

    @State private var data = CrisisData()
    @State private var step: Step = .intensity
    @State private var loaded = false
    @State private var activeSkill: TippSkill?
    @State private var showPlan = false

    private let accent = TherapyMethod.dbt.accent
    static let stillHighThreshold = 8

    private var steps: [Step] {
        var s: [Step] = [.intensity, .choose]
        switch data.skill {
        case .stop: s += [.stopS, .stopT, .stopO, .stopP]
        default: s.append(.tipp)
        }
        return s + [.rerate, .complete]
    }

    private var index: Int { steps.firstIndex(of: step) ?? 0 }

    var body: some View {
        StepScaffold(toolTitle: session.tool.title, accent: accent, stepID: step.rawValue,
                     position: index + 1, total: steps.count - 1,
                     showsProgress: step != .complete,
                     primaryTitle: primaryTitle, canContinue: canContinue,
                     secondaryTitle: step == .stopO ? "Skip" : nil,
                     onSecondary: { go(to: .stopP) },
                     onPrimary: primary,
                     onBack: backAction,
                     closesWithoutAsking: step == .complete,
                     onSaveForLater: callbacks.onClose,
                     onDiscard: callbacks.onDiscard) {
            content
        }
        .onAppear(perform: load)
        .onChange(of: data) { _, new in session.store(new) }
        .fullScreenCover(item: $activeSkill) { skill in
            TippExerciseView(skill: skill, accent: accent,
                             onDone: {
                                 if !data.tippDone.contains(skill) { data.tippDone.append(skill) }
                                 activeSkill = nil
                             },
                             onClose: { activeSkill = nil })
        }
        .sheet(isPresented: $showPlan) { SafetyPlanSheet() }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intensity:
            StepHeader(question: "How intense is it right now?",
                       helper: "A gut number, so you can see what the skill does.")
            TenPointScale(label: "Intensity", value: $data.intensityBefore,
                          anchors: [0: "Calm", 5: "Uncomfortable", 8: "Hard to think straight", 10: "Overwhelmed"])

        case .choose:
            StepHeader(question: "Which would help most right now?",
                       helper: (data.intensityBefore ?? 0) >= 8
                       ? "At this intensity, TIPP usually works fastest: it changes your body first."
                       : "Both work. Pick whichever feels doable.")
            ChoiceCard(title: "TIPP", detail: "Change your body chemistry fast: cold water, hard movement, slow breathing, or muscle release.",
                       symbol: "drop", accent: accent, selected: data.skill == .tipp, large: true) {
                data.skill = .tipp
            }
            ChoiceCard(title: "STOP", detail: "Pause before acting on the feeling: stop, step back, observe, then choose.",
                       symbol: "hand.raised", accent: accent, selected: data.skill == .stop, large: true) {
                data.skill = .stop
            }

        case .tipp:
            StepHeader(question: "Try one, or a few.",
                       helper: "Each takes a minute or two. Tap one to start.")
            VStack(spacing: 12) {
                ForEach(TippSkill.allCases) { skill in
                    ChoiceCard(title: skill.title, detail: skill.summary, symbol: skill.symbol, accent: accent,
                               selected: data.tippDone.contains(skill)) {
                        activeSkill = skill
                    }
                }
            }

        case .stopS:
            letterStep("S", "Stop.",
                       "Freeze. Don't act on the feeling yet, and don't say anything. Stay still for a moment.")
        case .stopT:
            letterStep("T", "Take a step back.",
                       "Take a slow breath. Step away from the situation, even if it's only in your head.")
        case .stopO:
            letterStep("O", "Observe.",
                       "What's happening inside you and around you? Just notice, without judging it.")
            FlowTextField(placeholder: "I notice…", text: $data.observe, minLines: 2)
        case .stopP:
            letterStep("P", "Proceed mindfully.",
                       "What action would make the situation better, not worse?")
            FlowTextField(placeholder: "What I'll do…", text: $data.proceed, minLines: 2)

        case .rerate:
            StepHeader(question: "How intense is it now?",
                       helper: "Whatever it is is fine. Even a point or two down counts.")
            if let before = data.intensityBefore {
                Text("Before: \(before)")
                    .font(.flowCaption)
                    .foregroundStyle(Ink.tertiary)
            }
            TenPointScale(label: "Intensity now", value: $data.intensityAfter,
                          anchors: [0: "Calm", 5: "Uncomfortable", 8: "Hard to think straight", 10: "Overwhelmed"])

        case .complete:
            completion
        }
    }

    private func letterStep(_ letter: String, _ title: String, _ helper: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(letter)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            StepHeader(question: title, helper: helper, large: true)
        }
    }

    private var stillHigh: Bool { (data.intensityAfter ?? 0) >= Self.stillHighThreshold }

    private var completion: some View {
        CompletionContent(
            title: stillHigh ? "Still very intense" : "You got through it",
            subtitle: stillHigh ? "That happens. Another skill, or reaching out, can help." : nil,
            rows: data.intensityBefore.map {
                [ChangeRow(label: "Intensity", before: Double($0), after: data.intensityAfter.map(Double.init), scale: .outOf10)]
            } ?? [],
            accent: accent
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if stillHigh {
                    NextStepButton(title: "Try another skill", symbol: "arrow.counterclockwise") {
                        data.intensityBefore = data.intensityAfter
                        data.intensityAfter = nil
                        session.status = .draft
                        go(to: .choose)
                    }
                    NextStepButton(title: "Your safety plan", detail: "Your warning signs, ways to cope, and people to reach.",
                                   symbol: "list.bullet.clipboard") { showPlan = true }
                    CrisisResourceCards()
                } else if let then = session.followUpTool {
                    CapsLabel("One optional next step")
                    NextStepButton(title: "Continue with \(then.title)",
                                   detail: "Now that it's calmer, you can work on the thought itself.",
                                   symbol: then.symbol) {
                        callbacks.onNext(.start(then, TherapyLaunch(
                            sourceEntryID: session.sourceEntryID, sourceCaptureID: session.sourceCaptureID,
                            targetThought: session.targetThought, triage: session.triage)))
                    }
                }
            }
        }
    }

    // MARK: Navigation

    private var primaryTitle: String {
        switch step {
        case .tipp: data.tippDone.isEmpty ? "Skip to rating" : "I'm done"
        case .rerate: "Finish"
        case .complete: "Done"
        default: "Next"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .intensity: data.intensityBefore != nil
        case .choose: data.skill != nil
        case .rerate: data.intensityAfter != nil
        default: true
        }
    }

    private var backAction: (() -> Void)? {
        if step == .complete { return nil }
        if index == 0 { return callbacks.onBackFromStart }
        return { go(to: steps[index - 1]) }
    }

    private func primary() {
        switch step {
        case .complete:
            callbacks.onNext(.done)
        case .intensity:
            if data.skill == nil, (data.intensityBefore ?? 0) >= 8 { data.skill = .tipp }
            go(to: .choose)
        case .rerate:
            SessionService.complete(session,
                                    metricBefore: data.intensityBefore.map { Double($0) * 10 },
                                    metricAfter: data.intensityAfter.map { Double($0) * 10 },
                                    in: modelContext)
            go(to: .complete)
        default:
            safetyGate.check(data) { go(to: steps[min(index + 1, steps.count - 1)]) }
        }
    }

    private func go(to newStep: Step) {
        hideKeyboard()
        withAnimation(.gentle) { step = newStep }
        let position = (steps.firstIndex(of: newStep) ?? 0) + 1
        session.record(step: newStep.rawValue, position: position, total: steps.count - 1)
        try? modelContext.save()
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        data = session.decode(CrisisData.self) ?? CrisisData()
        step = Step(rawValue: session.stepKey) ?? .intensity
        if session.status == .complete { step = .complete }
    }
}
