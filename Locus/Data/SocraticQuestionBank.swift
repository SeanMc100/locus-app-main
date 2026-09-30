import Foundation

// Editable data: the guiding questions shown on each step's "Socratic
// prompt card". These always work offline; when AI is on, a question
// written for this step may be shown first, and these follow.
// Questions only. Nothing here should hint at what the answer should be.

enum SocraticStep: String, Codable, CaseIterable, Sendable {
    case situation, automaticThought, evidenceFor, evidenceAgainst, balancedThought
    case prediction, alternativePrediction, experimentPlan, experimentLearning
    case interpretations, threat, catastrophe, problemSolving, oppositeAction
    case chainLinks, weakLink, repair
    case defusionBridge, committedStep, barriers, activity
}

enum SocraticQuestionBank {
    static func questions(for step: SocraticStep) -> [String] {
        switch step {
        case .situation:
            ["If a camera had filmed it, what would it show?",
             "Where were you, and who was there?",
             "What happened just before the feeling started?"]
        case .automaticThought:
            ["What was going through your mind right then?",
             "What were you afraid might happen?",
             "What does this say about you, if it's true?",
             "What's the worst part of this for you?"]
        case .evidenceFor:
            ["Would this hold up if a neutral observer looked at it?",
             "Which of these are facts, and which are how it felt?",
             "What actually happened that points this way?",
             "If you had to prove this in court, what would you show?"]
        case .evidenceAgainst:
            ["What would you tell a friend who had this thought?",
             "Have there been times this wasn't true?",
             "What are you ignoring because it doesn't fit?",
             "Is there another explanation?",
             "How will you see this in a year?",
             "What would someone who cares about you point out?"]
        case .balancedThought:
            ["Putting the evidence for and against side by side, what seems most likely?",
             "What would you say that's both honest and fair?",
             "What part of the original thought is true, and what part goes beyond the facts?",
             "If you were being fair to yourself, how would you put it?"]
        case .prediction:
            ["How would you know, for sure, that it happened?",
             "What would someone else notice?"]
        case .alternativePrediction:
            ["What's happened in similar situations before?",
             "What would a friend expect to happen?",
             "What's the most likely outcome, not the worst or the best?"]
        case .experimentPlan:
            ["What's the smallest version of this you could try?",
             "When would it be realistic to try it?",
             "What would you need to watch for to know how it went?"]
        case .experimentLearning:
            ["What surprised you?",
             "What does this tell you about the prediction?",
             "What would you tell yourself before the next one?"]
        case .interpretations:
            ["What else could this mean?",
             "How might someone else read the same event?",
             "What are you adding that isn't in the facts?"]
        case .threat:
            ["What exactly are you afraid will happen?",
             "How often has this actually happened before?",
             "What would have to be true for it to happen?"]
        case .catastrophe:
            ["If the worst happened, what would you do first?",
             "Who or what could help you cope?",
             "Have you got through something like this before?"]
        case .problemSolving:
            ["What's one thing within your control here?",
             "What would you suggest to a friend in this situation?",
             "What's a first step you could take today?"]
        case .oppositeAction:
            ["What would acting against this urge look like, specifically?",
             "What would you do if the emotion weren't steering?",
             "What's a version of this you could do today?"]
        case .chainLinks:
            ["What happened next?",
             "What were you thinking at that moment?",
             "What did you notice in your body?",
             "What did you feel pulled to do?"]
        case .weakLink:
            ["At this point, what might have changed the direction?",
             "What would you want to try here next time?",
             "Which skill fits this moment?"]
        case .repair:
            ["Is there anyone affected who you'd like to make things right with?",
             "What would repair look like, in a small, real way?"]
        case .defusionBridge:
            ["What matters to you in this situation?",
             "Who do you want to be here, whatever the thought says?",
             "If the thought had no grip at all, what would you do?"]
        case .committedStep:
            ["What could you do in the next day or two?",
             "What's small enough that you'd actually do it?",
             "What would someone who holds this value do next?"]
        case .barriers:
            ["What might your mind say to talk you out of it?",
             "Which feeling is most likely to show up?",
             "What usually gets in the way?"]
        case .activity:
            ["What used to lift your mood, even a little?",
             "What could you finish in ten minutes?",
             "Who could you connect with briefly?"]
        }
    }
}
