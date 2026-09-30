import SwiftUI

/// One guiding question for the step, with "Show another question". The
/// offline bank (`SocraticQuestionBank`) always works; with AI on, a
/// question written for this thought may come first.
struct SocraticPromptCard: View {
    let step: SocraticStep
    var context = SocraticContext()

    @State private var index = 0
    @State private var aiQuestion: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var questions: [String] {
        let bank = SocraticQuestionBank.questions(for: step)
        guard let aiQuestion, !bank.contains(aiQuestion) else { return bank }
        return [aiQuestion] + bank
    }

    var body: some View {
        let all = questions
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble")
                    .accessibilityHidden(true)
                CapsLabel("A question to consider")
            }
            .foregroundStyle(Ink.tertiary)
            Text(all.isEmpty ? "" : all[index % all.count])
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Ink.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .id(index)
                .transition(reduceMotion ? .identity : .opacity)
            if all.count > 1 {
                Button {
                    withAnimation(.gentle) { index += 1 }
                } label: {
                    Label("Show another question", systemImage: "arrow.triangle.2.circlepath")
                        .font(.flowCaption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(filled: true)
        .task(id: step) {
            guard TherapyAI.isEnabled else { return }
            if let q = await TherapyAI.socraticQuestion(step: step, context: context) {
                withAnimation(.gentle) {
                    aiQuestion = q
                    index = 0
                }
            }
        }
    }
}
