import SwiftUI
import SwiftData

/// Something to present in a full-screen skills flow.
struct FlowLaunch: Identifiable {
    let id = UUID()
    let start: TherapyFlowHost.Start
}

/// The toolkit's home: calm-down and quick capture up top, then the inbox,
/// in-progress work, today's diary card, insights, and the safety plan.
/// The journal stays the app's front page; this opens from its toolbar.
struct ToolkitHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("skills.onboardingSeen") private var onboardingSeen = false

    @State private var flow: FlowLaunch?
    @State private var showSafetyPlan = false
    @State private var showSettings = false
    @State private var showDiary = false
    @State private var showCapture = false
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top, spacing: 12) {
                        BigActionButton(title: "Quick capture", symbol: "bolt", accent: TherapyMethod.cbt.accent) {
                            showCapture = true
                        }
                        BigActionButton(title: "I need to calm down", symbol: "wind", accent: TherapyMethod.dbt.accent) {
                            flow = FlowLaunch(start: .tool(.crisisSkills, TherapyLaunch()))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    InboxSection { capture in
                        flow = FlowLaunch(start: .fresh(capture.launch))
                    }

                    InProgressSection { flow = FlowLaunch(start: .resume($0)) }

                    VStack(alignment: .leading, spacing: 12) {
                        CapsLabel("Today")
                        DiaryCardRow { showDiary = true }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        CapsLabel("Skills")
                        ChoiceCard(title: "Work through something",
                                   detail: "Pick an approach, or let the app help you choose.",
                                   symbol: "arrow.triangle.branch") {
                            flow = FlowLaunch(start: .fresh(TherapyLaunch()))
                        }
                        NavigationLink {
                            InsightsView()
                        } label: {
                            NavigationCardLabel(title: "Insights",
                                                detail: "Your belief ledger, predictions, patterns, values, and practice.",
                                                symbol: "chart.line.uptrend.xyaxis")
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        CapsLabel("Safety")
                        ChoiceCard(title: "Safety plan",
                                   detail: "Your warning signs, ways to cope, and people to reach.",
                                   symbol: "list.bullet.clipboard") {
                            showSafetyPlan = true
                        }
                    }

                    Text("A self-help skills tool, not a replacement for professional care.")
                        .font(.flowCaption)
                        .foregroundStyle(Ink.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Color.white)
            .navigationTitle("Toolkit")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showSafetyPlan) { SafetyPlanSheet() }
            .sheet(isPresented: $showSettings) { SkillsSettingsView() }
            .sheet(isPresented: $showDiary) { DiaryCardView() }
            .sheet(isPresented: $showCapture) {
                QuickCaptureView {
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        flow = FlowLaunch(start: .tool(.crisisSkills, TherapyLaunch()))
                    }
                }
            }
            .sheet(isPresented: $showOnboarding) {
                SkillsOnboardingView {
                    onboardingSeen = true
                    showOnboarding = false
                }
            }
            .fullScreenCover(item: $flow) { launch in
                TherapyFlowHost(start: launch.start) { flow = nil }
            }
            .onAppear {
                if !onboardingSeen { showOnboarding = true }
            }
        }
    }
}

/// A big square-ish button for the two "in the moment" actions.
struct BigActionButton: View {
    let title: String
    let symbol: String
    var accent: Color = .black
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: 110)
            .contentShape(Rectangle())
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// `ChoiceCard`'s look, for use as a NavigationLink label.
struct NavigationCardLabel: View {
    let title: String
    var detail: String? = nil
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .frame(width: 28)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.body, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.flowHelper)
                        .foregroundStyle(Ink.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.tertiary)
                .padding(.top, 4)
        }
        .foregroundStyle(Ink.primary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// Today's diary card status. Its own view so the query lives here and not
/// in the home's body (which owns navigation destinations).
private struct DiaryCardRow: View {
    let action: () -> Void
    @Query(sort: \DiaryCard.day, order: .reverse) private var diaryCards: [DiaryCard]

    private var doneToday: Bool {
        diaryCards.first.map { Calendar.current.isDateInToday($0.day) } ?? false
    }

    var body: some View {
        ChoiceCard(title: "Diary card",
                   detail: doneToday ? "Done today. Tap to edit." : "Not filled in yet. Takes under a minute.",
                   symbol: doneToday ? "checkmark.circle" : "square.and.pencil",
                   action: action)
    }
}
