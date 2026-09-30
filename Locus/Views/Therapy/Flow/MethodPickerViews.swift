import SwiftUI

/// Three large method cards plus a smaller "Help me choose".
struct MethodPickerView: View {
    let targetThought: String
    var suggestCrisis = false
    let onPick: (TherapyMethod) -> Void
    let onCrisis: () -> Void
    let onHelpMeChoose: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                StepHeader(question: "How do you want to work through this?",
                           helper: "Pick the approach that fits how it feels right now. You can always try another.",
                           large: true)

                TargetThoughtCard(thought: targetThought)

                if suggestCrisis {
                    VStack(alignment: .leading, spacing: 10) {
                        CapsLabel("Suggested right now")
                        ChoiceCard(title: TherapyTool.crisisSkills.title,
                                   detail: "Bring the intensity down first. Thinking work can wait until it's easier.",
                                   symbol: TherapyTool.crisisSkills.symbol,
                                   accent: TherapyMethod.dbt.accent,
                                   large: true,
                                   action: onCrisis)
                    }
                }

                VStack(spacing: 12) {
                    ForEach(TherapyMethod.allCases) { method in
                        MethodCard(method: method) { onPick(method) }
                    }
                }

                Button(action: onHelpMeChoose) {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                        Text("Help me choose")
                    }
                    .font(.flowButton)
                    .foregroundStyle(Ink.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", action: onClose)
            }
        }
    }
}

private struct MethodCard: View {
    let method: TherapyMethod
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(method.accent).frame(width: 9, height: 9)
                    Text(method.name)
                        .font(.flowLabel)
                        .tracking(1)
                        .foregroundStyle(method.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ink.tertiary)
                }
                Text(method.headline)
                    .font(.flowSection)
                    .foregroundStyle(Ink.primary)
                Text(method.useWhen)
                    .font(.flowHelper)
                    .foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(method.name): \(method.headline). \(method.useWhen)")
        .accessibilityAddTraits(.isButton)
    }
}

/// One method's tools, each with its "use when" line.
struct ToolPickerView: View {
    let method: TherapyMethod
    var targetThought = ""
    let onPick: (TherapyTool) -> Void
    var onBack: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(method.accent).frame(width: 9, height: 9)
                        Text(method.name)
                            .font(.flowLabel)
                            .tracking(1)
                            .foregroundStyle(method.accent)
                    }
                    StepHeader(question: method.headline, helper: "Choose a tool.", large: true)
                }
                TargetThoughtCard(thought: targetThought, accent: method.accent)
                VStack(spacing: 12) {
                    ForEach(method.tools) { tool in
                        ChoiceCard(title: tool.title, detail: tool.useWhen, symbol: tool.symbol,
                                   accent: method.accent) { onPick(tool) }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let onBack {
                    Button("Back", action: onBack)
                } else {
                    Button("Close", action: onClose)
                }
            }
            if onBack != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
    }
}

// MARK: - Help me choose

struct TriageIntensityView: View {
    @Binding var value: Int?
    let onNext: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        TriageFrame(position: 1, canContinue: value != nil, onNext: onNext, onBack: onBack, onClose: onClose) {
            StepHeader(question: "How intense is the feeling right now?",
                       helper: "Just a gut number. It helps pick where to start.",
                       large: true)
            TenPointScale(label: "Intensity", value: $value,
                          anchors: [0: "Calm", 5: "Uncomfortable", 8: "Hard to think straight", 10: "Overwhelmed"])
        }
    }
}

struct TriageKindView: View {
    @Binding var selection: TriageAnswers.ThoughtKind?
    let onNext: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        TriageFrame(position: 2, canContinue: selection != nil, onNext: onNext, onBack: onBack, onClose: onClose) {
            StepHeader(question: "What kind of thought is it?", large: true)
            VStack(spacing: 12) {
                ForEach(TriageAnswers.ThoughtKind.allCases, id: \.self) { kind in
                    ChoiceCard(title: kind.label, detail: kind.example.map { "e.g. \($0)" },
                               selected: selection == kind, large: true) {
                        selection = kind
                    }
                }
            }
        }
    }
}

struct RecommendationView: View {
    let recommendation: MethodRecommendation
    let onStart: () -> Void
    let onChooseElse: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        let tool = recommendation.tool
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CapsLabel("Suggested")
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle().fill(tool.method.accent).frame(width: 9, height: 9)
                        Text("\(tool.method.name) · \(tool.method.headline)")
                            .font(.flowLabel)
                            .foregroundStyle(tool.method.accent)
                    }
                    Text(tool.title)
                        .font(.flowTitle)
                    Text(recommendation.reason)
                        .font(.flowBody)
                        .foregroundStyle(Ink.primary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let then = recommendation.thenTool {
                    NoticeCard(text: "Afterwards, you can carry on with \(then.title) for the thought itself.",
                               symbol: "arrow.turn.down.right")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                PrimaryButton(title: "Start \(tool.title)", action: onStart)
                Button("Choose something else", action: onChooseElse)
                    .font(.flowButton)
                    .foregroundStyle(Ink.secondary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white.ignoresSafeArea())
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", action: onBack)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", action: onClose)
            }
        }
    }
}

private struct TriageFrame<Content: View>: View {
    let position: Int
    let canContinue: Bool
    let onNext: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            StepProgress(position: position, total: 2, accent: .black)
                .padding(.horizontal, 24)
                .padding(.top, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) { content }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.white)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Next", disabled: !canContinue, action: onNext)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.white.ignoresSafeArea())
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Help me choose").font(.system(.subheadline, weight: .semibold))
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", action: onBack)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onClose()
                } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Close")
            }
        }
    }
}
