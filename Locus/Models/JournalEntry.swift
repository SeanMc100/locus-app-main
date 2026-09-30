import Foundation
import SwiftData

/// A finished session: the journal text plus the results of whichever
/// flow ran: a question and the user's answer (question flow), the
/// judgement-flow results (stripped version, intensity ratings, and
/// optionally a friend reply or truer judgement), or the items the user
/// sorted (sort flow).
@Model
final class JournalEntry {
    var createdAt: Date = Date.now
    var text: String = ""
    var inControl: [String] = []
    var notInControl: [String] = []
    /// User-authored "what's mine instead" phrase per `notInControl` item,
    /// same order/length as `notInControl` (empty string = skipped). Older
    /// entries predate this field and may be shorter or empty.
    var counterparts: [String] = []
    /// Answer to "What would you say to a friend who told you this?"
    /// (friend-reply flow). Empty for sort-flow entries.
    var friendReply: String = ""
    /// Judgement quotes the AI found in `text` (friend-reply flow), kept so
    /// highlights can be re-shown in history.
    var judgements: [String] = []
    /// `text` with those judgements cut out, minimally repaired.
    var withoutJudgements: String = ""
    /// How strongly the user felt it (0–10) right after writing, and again
    /// after reading `withoutJudgements`. Nil if not rated (sort flow,
    /// older entries, or no stripped version to re-rate against).
    var intensityBefore: Int? = nil
    var intensityAfter: Int? = nil
    /// The truer judgement, user-authored and addressed to themselves
    /// (the alternative to `friendReply` on the last step).
    var truerJudgement: String = ""
    /// The question asked after writing (question flow), and the user's
    /// written answer.
    var question: String = ""
    var questionAnswer: String = ""
    /// `QuestionMove.id` the question came from ("none" if nothing fit),
    /// used to rotate moves across sessions.
    var questionMove: String = ""
    /// Testing diagnostics: the entry's state, move, and crux.
    var questionNotes: String = ""
    /// Stable id that skills sessions (kept on this device only) use to
    /// link back to this entry. Empty until first linked: it's assigned
    /// lazily so older entries don't all migrate to the same default.
    var linkID: String = ""
    /// "saved" for entries saved by the skills post-entry flow
    /// (`FeatureFlags.useLegacyPostEntryFlow == false`); "" for entries
    /// from the legacy flows.
    var postEntryFlow: String = ""

    /// Sort-flow entries predate the judgement flow; everything
    /// judgement-related is empty on them.
    var isSortFlow: Bool {
        if !postEntryFlow.isEmpty { return false }
        return !inControl.isEmpty || !notInControl.isEmpty
            || (friendReply.isEmpty && truerJudgement.isEmpty && judgements.isEmpty
                && withoutJudgements.isEmpty && intensityBefore == nil && question.isEmpty)
    }

    init(createdAt: Date = .now, text: String, inControl: [String] = [], notInControl: [String] = [], counterparts: [String] = [], friendReply: String = "", judgements: [String] = [], withoutJudgements: String = "", intensityBefore: Int? = nil, intensityAfter: Int? = nil, truerJudgement: String = "", question: String = "", questionAnswer: String = "", questionMove: String = "", questionNotes: String = "", linkID: String = "", postEntryFlow: String = "") {
        self.createdAt = createdAt
        self.text = text
        self.inControl = inControl
        self.notInControl = notInControl
        self.counterparts = counterparts
        self.friendReply = friendReply
        self.judgements = judgements
        self.withoutJudgements = withoutJudgements
        self.intensityBefore = intensityBefore
        self.intensityAfter = intensityAfter
        self.truerJudgement = truerJudgement
        self.question = question
        self.questionAnswer = questionAnswer
        self.questionMove = questionMove
        self.questionNotes = questionNotes
        self.linkID = linkID
        self.postEntryFlow = postEntryFlow
    }

    /// `linkID`, assigned now if this entry hasn't been linked before.
    func ensureLinkID() -> String {
        if linkID.isEmpty { linkID = UUID().uuidString }
        return linkID
    }
}

/// An item pulled from the journal, editable before sorting.
struct ExtractedItem: Identifiable, Hashable {
    let id = UUID()
    var text: String
}
