import SwiftUI

/// Picks the flow for a session's tool.
struct ToolFlowView: View {
    let session: TherapySession
    let callbacks: FlowCallbacks

    var body: some View {
        switch session.tool {
        case .thoughtRecord:
            ThoughtRecordFlow(session: session, callbacks: callbacks)
        case .behavioralExperiment:
            ExperimentFlow(session: session, callbacks: callbacks)
        case .behavioralActivation:
            ActivationFlow(session: session, callbacks: callbacks)
        case .crisisSkills:
            CrisisSkillsFlow(session: session, callbacks: callbacks)
        case .checkTheFacts:
            CheckFactsFlow(session: session, callbacks: callbacks)
        case .oppositeAction:
            OppositeActionFlow(session: session, callbacks: callbacks)
        case .chainAnalysis:
            ChainAnalysisFlow(session: session, callbacks: callbacks)
        case .defusion:
            DefusionFlow(session: session, callbacks: callbacks)
        case .valuesCheckIn:
            ValuesCheckInFlow(session: session, callbacks: callbacks)
        case .committedAction:
            CommittedActionFlow(session: session, callbacks: callbacks)
        }
    }
}
