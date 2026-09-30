import Foundation

/// Central switches for flows that are being replaced but kept intact.
enum FeatureFlags {
    /// `true` restores the post-entry flow as it was before 2026-09-29:
    /// "Continue" after writing runs `SessionFlowView` (question, judgement,
    /// or sort flow, per `SessionFlowView.flow`), and none of the skills
    /// toolkit is shown.
    ///
    /// `false` (default): "Save" stores the entry, then offers "Work through
    /// this" (CBT / DBT / ACT skills, `TherapyFlowHost`). The legacy code
    /// all still compiles and is untouched.
    static let useLegacyPostEntryFlow = false

    /// Shorthand for the places that add toolkit UI to existing screens.
    static var showsSkillsToolkit: Bool { !useLegacyPostEntryFlow }
}
