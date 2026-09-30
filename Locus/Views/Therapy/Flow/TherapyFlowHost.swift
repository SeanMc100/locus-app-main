import SwiftUI
import SwiftData

/// Runs the skills flow in one full-screen cover: safety check -> method
/// picker (or "Help me choose") -> tool -> completion, and any next step a
/// completion offers. Also owns the safety gate every step goes through.
struct TherapyFlowHost: View {
    enum Start {
        /// From a journal entry, capture, or the toolkit: pick a method.
        case fresh(TherapyLaunch)
        /// Straight into one tool (e.g. "I need to calm down").
        case tool(TherapyTool, TherapyLaunch)
        /// Carry on with a draft or pending session.
        case resume(TherapySession)
        /// Straight to one method's tools.
        case method(TherapyMethod, TherapyLaunch)
    }

    let start: Start
    let onClose: () -> Void

    enum Route: Hashable {
        case methodPicker
        case toolPicker(TherapyMethod)
        case triageIntensity
        case triageKind
        case recommendation(MethodRecommendation)
        case session(TherapySession)
    }

    @Environment(\.modelContext) private var modelContext
    @AppStorage("skills.onboardingSeen") private var onboardingSeen = false

    @State private var path: [Route] = []
    @State private var launch = TherapyLaunch()
    @State private var triageIntensity: Int?
    @State private var triageKind: TriageAnswers.ThoughtKind?
    /// Risk found in what they wrote before starting: crisis skills are
    /// suggested first.
    @State private var riskAtLaunch = false
    @State private var showingSafety = false
    @State private var safetyProceed: (() -> Void)?
    @State private var acknowledgedMatches: Set<String> = []
    /// Payload of a session as it was created here, so backing out before
    /// entering anything doesn't leave an empty draft behind.
    @State private var untouchedPayloads: [UUID: Data] = [:]
    @State private var started = false
    @State private var showOnboarding = false

    private var current: Route { path.last ?? .methodPicker }

    var body: some View {
        NavigationStack {
            ZStack {
                if showingSafety {
                    SafetyResourcesView(onCalmDown: calmDownOption, onContinue: continueAfterSafety)
                        .transition(.opacity)
                } else {
                    routeView(current)
                        .id(routeID(current))
                        .transition(.opacity)
                }
            }
            .animation(.gentle, value: showingSafety)
            .animation(.gentle, value: path)
        }
        .environment(\.safetyGate, SafetyGate { text, proceed in gate(text, proceed) })
        .onAppear(perform: begin)
        .sheet(isPresented: $showOnboarding) {
            SkillsOnboardingView {
                onboardingSeen = true
                showOnboarding = false
            }
        }
    }

    // MARK: Routes

    @ViewBuilder
    private func routeView(_ route: Route) -> some View {
        switch route {
        case .methodPicker:
            MethodPickerView(targetThought: launch.targetThought,
                             suggestCrisis: riskAtLaunch,
                             onPick: { path.append(.toolPicker($0)) },
                             onCrisis: { startSession(.crisisSkills) },
                             onHelpMeChoose: {
                                 triageIntensity = nil
                                 triageKind = nil
                                 path.append(.triageIntensity)
                             },
                             onClose: onClose)
        case .toolPicker(let method):
            ToolPickerView(method: method,
                           targetThought: launch.targetThought,
                           onPick: { startSession($0) },
                           onBack: path.count > 1 ? { path.removeLast() } : nil,
                           onClose: onClose)
        case .triageIntensity:
            TriageIntensityView(value: $triageIntensity,
                                onNext: { path.append(.triageKind) },
                                onBack: { path.removeLast() },
                                onClose: onClose)
        case .triageKind:
            TriageKindView(selection: $triageKind,
                           onNext: showRecommendation,
                           onBack: { path.removeLast() },
                           onClose: onClose)
        case .recommendation(let rec):
            RecommendationView(recommendation: rec,
                               onStart: {
                                   launch.triage = triageAnswers
                                   launch.followUpTool = rec.thenTool
                                   startSession(rec.tool)
                               },
                               onChooseElse: {
                                   launch.triage = triageAnswers
                                   path = [.methodPicker]
                               },
                               onBack: { path.removeLast() },
                               onClose: onClose)
        case .session(let session):
            ToolFlowView(session: session, callbacks: callbacks(for: session))
        }
    }

    private func routeID(_ route: Route) -> String {
        switch route {
        case .methodPicker: "methods"
        case .toolPicker(let m): "tools.\(m.rawValue)"
        case .triageIntensity: "triage.1"
        case .triageKind: "triage.2"
        case .recommendation: "triage.rec"
        case .session(let s): "session.\(s.idString)"
        }
    }

    private var triageAnswers: TriageAnswers? {
        guard let triageIntensity, let triageKind else { return nil }
        return TriageAnswers(intensity: triageIntensity, thoughtKind: triageKind)
    }

    private func showRecommendation() {
        guard let answers = triageAnswers else { return }
        let rec = MethodRouter.recommendMethod(answers, EntryContext(targetThought: launch.targetThought, entryText: launch.entryText))
        path.append(.recommendation(rec))
    }

    // MARK: Sessions

    private func begin() {
        guard !started else { return }
        started = true
        if !onboardingSeen { showOnboarding = true }
        switch start {
        case .fresh(let l):
            launch = l
            path = [.methodPicker]
            let text = [l.entryText, l.targetThought].joined(separator: "\n")
            let found = RiskDetector.assess(text)
            if found.isRisk {
                riskAtLaunch = true
                acknowledgedMatches = found.matches
                showingSafety = true
            } else {
                // AI (if on) can only escalate the offline result.
                Task {
                    let assessed = await TherapyAI.assessRisk(text)
                    if assessed.isRisk && !showingSafety {
                        riskAtLaunch = true
                        showingSafety = true
                    }
                }
            }
        case .tool(let tool, let l):
            launch = l
            startSession(tool, replacing: true)
        case .resume(let session):
            path = [.session(session)]
        case .method(let method, let l):
            launch = l
            path = [.toolPicker(method)]
        }
    }

    private func startSession(_ tool: TherapyTool, replacing: Bool = false) {
        let session = SessionService.start(tool, launch: launch, in: modelContext)
        untouchedPayloads[session.id] = session.payload
        if replacing { path = [.session(session)] } else { path.append(.session(session)) }
    }

    private func callbacks(for session: TherapySession) -> FlowCallbacks {
        let canGoBack = path.count > 1
        return FlowCallbacks(
            onBackFromStart: canGoBack ? {
                if let original = untouchedPayloads[session.id], original == session.payload {
                    SessionService.discard(session, in: modelContext)
                }
                path.removeLast()
            } : nil,
            onClose: {
                try? modelContext.save()
                onClose()
            },
            onDiscard: {
                SessionService.discard(session, in: modelContext)
                onClose()
            },
            onNext: { next in
                switch next {
                case .done:
                    onClose()
                case .start(let tool, let carry):
                    launch = carry
                    startSession(tool, replacing: true)
                }
            })
    }

    // MARK: Safety

    private func gate(_ text: String, _ proceed: @escaping () -> Void) {
        let found = RiskDetector.assess(text)
        let new = found.matches.subtracting(acknowledgedMatches)
        guard found.isRisk, !new.isEmpty else {
            proceed()
            return
        }
        acknowledgedMatches.formUnion(found.matches)
        safetyProceed = proceed
        showingSafety = true
    }

    private var currentSession: TherapySession? {
        if case .session(let s) = current { return s }
        return nil
    }

    /// Offered on the safety screen unless they're already in crisis skills.
    private var calmDownOption: (() -> Void)? {
        if currentSession?.tool == .crisisSkills { return nil }
        return {
            try? modelContext.save()
            showingSafety = false
            safetyProceed = nil
            var carry = launch
            carry.followUpTool = nil
            carry.triage = nil
            launch = carry
            startSession(.crisisSkills, replacing: true)
        }
    }

    private func continueAfterSafety() {
        showingSafety = false
        let proceed = safetyProceed
        safetyProceed = nil
        proceed?()
    }
}
