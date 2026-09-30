import Foundation
import FoundationModels

// The question library for the question flow. Edit freely: this file is
// data, not logic.
//
// How it's used (`QuestionAsker`): the model reads the entry and says what
// kind of moment it is (`EntryState`) and which belief most holds it up
// (the crux: a judgement in their words, never a plain fact). Moves that fit that state are ranked by the model, and the
// least recently used of its top three wins, so no single question wears
// out. Then the model chooses one question from that move's list.
//
// Questions are always asked as written here: the small on-device model
// writes clumsy questions but chooses well. `{crux}` is replaced with the
// writer's own words (checked to really be in the entry), so a question
// can still be about this entry and no other. Questions with `{crux}` are
// only offered when a crux was found, so every move needs at least one
// question without it, and the first question is the default if choosing
// fails. A question marked `only:` is offered just for those states, for
// ones that suit one kind of moment ("this urge" asked about grief).

/// What kind of moment an entry is. The reader picks one per entry; each
/// move lists the states it fits.
@Generable
enum EntryState: Hashable {
    case urge, selfCriticism, conflict, worry, regret, decision, loss
    case overwhelm, comparison, disappointment, settled, crisis, unclear
}

/// One way of shifting someone's headspace, with questions in its voice.
struct QuestionMove: Sendable {
    /// Stable id, saved on `JournalEntry.questionMove` and used for
    /// rotation. Renaming one loses its rotation history.
    let id: String
    let name: String
    /// The shift this move makes. Shown to the model when it ranks moves.
    let shift: String
    let fits: [EntryState]
    /// When not to pick this move even though the state fits. Shown to the
    /// model when it ranks moves.
    var avoidWhen = ""
    /// The first is the default, so it should suit every state in `fits`.
    /// `{crux}` = the writer's own words.
    let questions: [Question]
}

/// A plain string literal works for a question that suits every state the
/// move fits; `Question("…", only: [...])` limits it.
struct Question: Sendable, ExpressibleByStringLiteral {
    let text: String
    var only: [EntryState] = []

    init(_ text: String, only: [EntryState] = []) {
        self.text = text
        self.only = only
    }

    init(stringLiteral text: String) {
        self.text = text
    }

    func suits(_ state: EntryState) -> Bool {
        only.isEmpty || only.contains(state)
    }
}

enum QuestionMoves {

    /// Asked when no move fits the entry (the reader said `unclear`, the
    /// reading was blocked, or the model isn't available). Marked "no fit"
    /// in testing so the gaps are visible.
    static let noFitQuestion = "What's the part of this you haven't said yet?"

    static let all: [QuestionMove] = [

        // MARK: Distance

        QuestionMove(
            id: "friend",
            name: "Talk to a friend",
            shift: "Steps outside their own head. People are kinder and wiser about a friend's trouble than their own.",
            fits: [.selfCriticism, .disappointment, .regret, .comparison, .overwhelm, .worry],
            avoidWhen: "the entry is mostly about another person's behaviour rather than the writer's own situation",
            questions: [
                "What would you say to a friend who told you this?",
                "If a friend told you “{crux}”, what would you say back?",
                "If your closest friend showed you this exact entry, what would you want them to hear?",
                "What would you tell a friend who'd been going over this all day?",
                Question("If a friend were being this hard on themselves, what would you want them to know?",
                         only: [.selfCriticism, .regret, .comparison]),
            ]),

        QuestionMove(
            id: "futureLook",
            name: "Look back from later",
            shift: "Distance in time. Seen from a year or more away, what's temporary shrinks and what lasts stands out.",
            fits: [.worry, .disappointment, .conflict, .overwhelm, .regret, .decision],
            avoidWhen: "the writer is grieving or has lost something that will really matter for years; it can sound like \"this won't matter\"",
            questions: [
                "A year from now, looking back on this week, what do you hope you'll have done with it?",
                "Which part of this will still matter in five years, and which part won't?",
                "When this has blown over, what do you want to be able to say about how you handled it?",
                "How would you tell the story of this ten years from now?",
            ]),

        QuestionMove(
            id: "notAlone",
            name: "Not only you",
            shift: "From \"what's wrong with me\" to \"this is what being a person is like\".",
            fits: [.selfCriticism, .comparison, .disappointment, .loss, .regret],
            questions: [
                "How many people do you think felt exactly this today?",
                Question("How many people have thought “{crux}” at some point? Were they right?",
                         only: [.selfCriticism, .comparison, .disappointment, .regret]),
                Question("Who do you know who's been through something like this, and what did you think of them for it?",
                         only: [.selfCriticism, .comparison, .disappointment, .regret]),
                Question("Is this something wrong with you, or something that happens to people?",
                         only: [.selfCriticism, .comparison, .disappointment, .regret]),
                Question("Who else do you know who has lost something like this?", only: [.loss]),
            ]),

        // MARK: Facts

        QuestionMove(
            id: "evidence",
            name: "What actually happened",
            shift: "Separates what happened from the story laid over it.",
            fits: [.selfCriticism, .worry, .conflict, .disappointment, .comparison],
            avoidWhen: "the painful belief is plainly true (a real loss, a real mistake); questioning it would imply they're overreacting",
            questions: [
                "What do you know for certain here, and what are you filling in?",
                "You wrote “{crux}”. What did you actually see or hear that tells you that?",
                "If you had to prove “{crux}” to a stranger, what would you show them, and what would they say back?",
                "What actually happened, before you added anything to it?",
                "Which parts of this would a camera have recorded, and which parts came from you?",
            ]),

        QuestionMove(
            id: "andThen",
            name: "Follow it through",
            shift: "Walks a fear to its end, where it's usually more survivable than the dread of it.",
            fits: [.worry, .decision],
            avoidWhen: "the feared outcome is severe and realistic (a serious diagnosis, real danger)",
            questions: [
                "Say the thing you're dreading does happen. What would you do the day after?",
                "Suppose “{crux}” turns out to be true. Then what?",
                "If it really does go badly, what would you still have?",
                "What's the most likely way this plays out, rather than the worst?",
            ]),

        QuestionMove(
            id: "rightNow",
            name: "Right now",
            shift: "From the future or the past back to the present, where most of the trouble isn't.",
            fits: [.worry, .overwhelm, .regret],
            questions: [
                "Apart from the thoughts about it, what's actually happening right now?",
                "What's true in the room you're in, apart from what might happen?",
                "What's the one thing in front of you today, not this week?",
                "Is anything actually being asked of you in the next hour? What is it?",
            ]),

        // MARK: Control and choice

        QuestionMove(
            id: "control",
            name: "What's yours",
            shift: "The Stoic split between what's up to you and what isn't. Attention moves to the part you can act on.",
            fits: [.worry, .conflict, .overwhelm, .disappointment, .decision],
            questions: [
                "Of everything in this, which one piece is actually in your hands?",
                "You can't choose everything that lands on you. What can you choose about how you meet it?",
                "If you put down everything here that isn't up to you, what's left to pick up?",
                "What's the next small thing that's yours to do?",
                "How much of your energy is going to the parts of this you can't change?",
            ]),

        QuestionMove(
            id: "whoToBe",
            name: "Who you want to be",
            shift: "From what's happening to you to how you want to meet it.",
            fits: [.conflict, .decision, .urge, .disappointment, .overwhelm],
            questions: [
                "Whatever happens next, how do you want to have handled this?",
                "What would the person you're trying to become do tomorrow?",
                "Which choice here would you be proud of in a year?",
                "Whatever anyone else does, what kind of person do you want to be in this?",
            ]),

        QuestionMove(
            id: "wisestYou",
            name: "Ask the wiser one",
            shift: "Borrows the calm of someone the writer admires, or of their own best self.",
            // Not for urges: "trust yourself" can read as permission.
            fits: [.decision, .conflict, .overwhelm],
            questions: [
                "What would the wisest person you know tell you to do?",
                "What would you do here if you weren't afraid?",
                "If you already knew the answer, what would it be?",
                "What would you do if you trusted yourself completely?",
            ]),

        QuestionMove(
            id: "training",
            name: "What it's practice for",
            shift: "The obstacle as training. The same situation, seen as a chance to practise something.",
            fits: [.conflict, .disappointment, .overwhelm, .worry],
            avoidWhen: "the writer is grieving or in real hardship; it can sound like a silver lining forced on them",
            questions: [
                "If this were practice for something, what would it be practice for?",
                "What's this a chance to get better at?",
                "What would handling this well look like, rather than just getting through it?",
            ]),

        // MARK: Urges

        QuestionMove(
            id: "burdenFlip",
            name: "Argue the other side",
            shift: "Moves the burden of proof. Instead of the urge arguing for itself, the writer argues against it in their own words.",
            fits: [.urge, .decision],
            questions: [
                "Why shouldn't you do this?",
                "What's the strongest reason not to, in your own words?",
                Question("If you don't do this tonight, what are you choosing instead?", only: [.urge]),
                "What would you need to believe for this to be a good idea, and do you believe it?",
            ]),

        QuestionMove(
            id: "playTheTape",
            name: "Play it forward",
            shift: "Pulls the aftermath into the present, where the urge can't hide it.",
            fits: [.urge],
            questions: [
                "Picture an hour after you've done it. What does that version of you wish you'd done instead?",
                "How will tomorrow morning feel if you do this, and if you don't?",
                "The last time you gave in to this, how did the next day go?",
                "What will you be telling yourself about this tomorrow?",
            ]),

        QuestionMove(
            id: "needUnderneath",
            name: "The need underneath",
            shift: "Looks past the behaviour or the complaint to what's actually being sought.",
            fits: [.urge, .overwhelm, .conflict, .loss],
            questions: [
                "What do you actually need right now that you're not getting?",
                Question("What is this urge trying to get for you, and is there another way to get it?", only: [.urge]),
                "If this feeling could ask for one thing, what would it ask for?",
                Question("Underneath the frustration, what were you hoping for?", only: [.conflict, .overwhelm]),
                "What would actually help tonight, even a little?",
            ]),

        QuestionMove(
            id: "inversion",
            name: "How to make it worse",
            shift: "Inversion. Asking how to make things worse shows what the writer may already be doing to keep it going.",
            fits: [.overwhelm, .regret, .worry, .urge],
            avoidWhen: "the writer is very low or already blaming themselves harshly; it can read as blame",
            questions: [
                "If you wanted to feel even worse about this tomorrow, what would you do tonight? Are you doing any of it?",
                "What's the surest way to keep this going round in your head? Is that what you're doing?",
                "If you wanted this to drag on for months, what would you keep doing?",
            ]),

        // MARK: Other people

        QuestionMove(
            id: "otherSide",
            name: "Their side of it",
            shift: "Steps into the other person's shoes, which loosens certainty about their motives.",
            fits: [.conflict],
            avoidWhen: "the other person has been abusive, cruel, or unsafe; the writer doesn't owe them a generous reading",
            questions: [
                "What might be going on for them that you can't see from where you're standing?",
                "What's the most generous explanation for what they did that could still be true?",
                "How do you think they'd tell the story of today?",
                "If they wrote about this tonight, what would their entry say?",
            ]),

        // MARK: Meaning and acceptance

        QuestionMove(
            id: "whatItShows",
            name: "What the hurt points to",
            shift: "Treats pain as information about what the writer values, not as a verdict on them.",
            fits: [.disappointment, .comparison, .selfCriticism, .regret],
            avoidWhen: "the writer is grieving; they already know it mattered",
            questions: [
                "What does how much this hurts tell you about what matters to you?",
                "If you didn't care about this, it wouldn't sting. What do you care about here?",
                Question("What is the envy pointing at that you actually want for yourself?", only: [.comparison]),
                "Underneath “{crux}”, what is it you really want?",
            ]),

        QuestionMove(
            id: "stopArguing",
            name: "If it doesn't change",
            shift: "Acceptance. Stops the fight with what already happened or can't be changed, which frees energy for what can.",
            // Not for loss: the ranker can't tell fresh grief from old, and
            // "stop arguing with it" to fresh grief is cruel.
            fits: [.regret, .conflict, .disappointment],
            avoidWhen: "the situation can still be changed and the writer could act on it",
            questions: [
                "If this part never changes, what would living well alongside it look like?",
                "What would it be like to stop arguing with the fact that it happened?",
                "What are you still hoping could have gone differently, and what would it take to let that go?",
            ]),

        QuestionMove(
            id: "whatToKeep",
            name: "What to keep",
            shift: "For grief. Turns from the loss toward what it held.",
            fits: [.loss],
            questions: [
                "What did this give you that you don't want to forget?",
                "What do you most want to carry with you from what you've lost?",
                "What's one moment you want to hold on to?",
                "If you could say one more thing to them, what would it be?",
            ]),

        // MARK: Settled days

        QuestionMove(
            id: "eveningReview",
            name: "Evening review",
            shift: "Seneca's evening review. An honest look back at the day, without harshness, to learn from it.",
            fits: [.settled, .regret],
            questions: [
                "What did you do well today, and what would you do differently?",
                "Where were you at your best today, and what made that possible?",
                Question("What part of today's good mood came from something you did?", only: [.settled]),
                "What's one thing from today you'd like to do again tomorrow?",
            ]),

        QuestionMove(
            id: "wouldMiss",
            name: "What you'd miss",
            shift: "Negative visualisation. Imagining losing what you have makes it visible again.",
            fits: [.settled, .comparison, .overwhelm],
            avoidWhen: "the writer is grieving or afraid of losing something; don't hand them a new fear",
            questions: [
                "What in today would you miss if it were gone tomorrow?",
                "What do you have right now that you once hoped for?",
                "If this were the last ordinary week like this, what would you notice about it?",
            ]),

        // MARK: Safety

        QuestionMove(
            id: "reachOut",
            name: "Reach out",
            shift: "When someone may not be safe, the question is about connection, not perspective.",
            fits: [.crisis],
            questions: [
                "This sounds like a lot to carry alone. Who is one person you could reach out to tonight?",
            ]),
    ]

    static func move(id: String) -> QuestionMove? {
        all.first { $0.id == id }
    }
}
