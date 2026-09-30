import SwiftUI
import SwiftData

/// Shown when the risk check finds something. Calm, never blocking: the
/// user can always carry on. Nothing here is AI-generated, and the copy
/// makes no promises about what crisis services will or won't do.
struct SafetyResourcesView: View {
    /// Primary suggestion: a calming skill instead of cognitive work.
    var onCalmDown: (() -> Void)?
    let onContinue: () -> Void

    @State private var showPlan = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "heart")
                        .font(.system(size: 28, weight: .light))
                        .accessibilityHidden(true)
                    Text("It sounds like things might be really hard right now.")
                        .font(.flowTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("You don't have to go through this alone.")
                        .font(.system(.title3))
                        .foregroundStyle(Ink.secondary)
                }

                CrisisResourceCards(onSafetyPlan: { showPlan = true })

                VStack(spacing: 12) {
                    if let onCalmDown {
                        PrimaryButton(title: "Try a calming skill", action: onCalmDown)
                    }
                    Button("Continue", action: onContinue)
                        .font(.flowButton)
                        .foregroundStyle(Ink.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $showPlan) { SafetyPlanSheet() }
    }
}

/// 988, Crisis Text Line, the safety plan, and 911. Shared by the safety
/// screen, the Safety Plan, and crisis-skill completion.
struct CrisisResourceCards: View {
    var onSafetyPlan: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            resourceCard(title: "988 Suicide & Crisis Lifeline",
                         detail: "Call or text 988 (US).") {
                HStack(spacing: 8) {
                    linkButton("Call 988", url: "tel:988", symbol: "phone.fill")
                    linkButton("Text 988", url: "sms:988", symbol: "message.fill")
                }
            }
            resourceCard(title: "Crisis Text Line",
                         detail: "Text HOME to 741741.") {
                linkButton("Text HOME to 741741", url: "sms:741741&body=HOME", symbol: "message.fill")
            }
            if let onSafetyPlan {
                Button(action: onSafetyPlan) {
                    HStack {
                        Image(systemName: "list.bullet.clipboard")
                        Text("Your safety plan")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .font(.flowBody)
                    .foregroundStyle(Ink.primary)
                    .padding(16)
                    .card()
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("If you're in immediate danger, call 911.")
                    .font(.system(.body, weight: .semibold))
                Spacer()
                Link(destination: URL(string: "tel:911")!) {
                    Text("Call 911")
                        .font(.flowButton)
                        .foregroundStyle(Ink.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().strokeBorder(Color.black))
                }
            }
            .padding(16)
            .card(filled: true)
        }
    }

    private func resourceCard<Actions: View>(title: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.body, weight: .semibold))
                Text(detail)
                    .font(.flowHelper)
                    .foregroundStyle(Ink.secondary)
            }
            actions()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func linkButton(_ title: String, url: String, symbol: String) -> some View {
        Link(destination: URL(string: url)!) {
            Label(title, systemImage: symbol)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black))
        }
    }
}

/// The Safety Plan in its own navigation stack, for presenting as a sheet
/// from anywhere.
struct SafetyPlanSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SafetyPlanView()
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        KeyboardHideButton()
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
    }
}

/// Stanley-Brown safety plan: seven fill-in sections, saved as you type.
struct SafetyPlanView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var plan: SafetyPlan?

    var body: some View {
        Group {
            if let plan {
                SafetyPlanForm(plan: plan)
            } else {
                Color.white
            }
        }
        .navigationTitle("Safety plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            plan = modelContext.singleton { SafetyPlan() }
        }
        .onDisappear { try? modelContext.save() }
    }
}

private struct SafetyPlanForm: View {
    @Bindable var plan: SafetyPlan
    @State private var contacts: [SafetyContact] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your safety plan")
                        .font(.flowTitle)
                    Text("Fill this in on a calmer day, so it's ready when things are hard. It stays on this device.")
                        .font(.flowHelper)
                        .foregroundStyle(Ink.secondary)
                }

                section(1, "My warning signs",
                        helper: "Thoughts, feelings, or situations that tell you a crisis may be starting.",
                        text: $plan.warningSigns)
                section(2, "Things I can do on my own to cope",
                        helper: "Ways to take your mind off things without contacting anyone.",
                        text: $plan.copingAlone)
                section(3, "People and places that can help distract me",
                        helper: "Where you can be around others, even without talking about it.",
                        text: $plan.distractions)

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(4, "People I can ask for help")
                    ForEach($contacts) { $contact in
                        ContactRow(contact: $contact) {
                            contacts.removeAll { $0.id == contact.id }
                        }
                    }
                    SecondaryButton(title: "Add a person", symbol: "plus") {
                        contacts.append(SafetyContact())
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(5, "Professionals or agencies I can contact")
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("988 Suicide & Crisis Lifeline")
                                .font(.system(.body, weight: .semibold))
                            Text("Call or text 988 (US)")
                                .font(.flowCaption)
                                .foregroundStyle(Ink.secondary)
                        }
                        Spacer()
                        Link("Call", destination: URL(string: "tel:988")!)
                            .font(.flowButton)
                    }
                    .padding(14)
                    .card(filled: true)
                    FlowTextField(placeholder: "Therapist, doctor, local services…", text: $plan.professionals,
                                  accessibilityLabel: "Professionals or agencies I can contact")
                }

                section(6, "Making my environment safer",
                        helper: "Steps to make it harder to act on urges when you're struggling.",
                        text: $plan.environment)
                section(7, "My reasons for living",
                        helper: "The people, things, and hopes that matter to you.",
                        text: $plan.reasonsForLiving)

                VStack(alignment: .leading, spacing: 12) {
                    CapsLabel("If you need help now")
                    CrisisResourceCards()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.white)
        .onAppear { contacts = plan.contacts }
        .onChange(of: contacts) { plan.contacts = contacts; plan.updatedAt = .now }
        .onChange(of: plan.warningSigns) { plan.updatedAt = .now }
    }

    private func sectionTitle(_ n: Int, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.system(.subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Ink.tertiary)
            Text(title)
                .font(.flowSection)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func section(_ n: Int, _ title: String, helper: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(n, title)
            Text(helper)
                .font(.flowHelper)
                .foregroundStyle(Ink.secondary)
            FlowTextField(placeholder: "Write here…", text: text, accessibilityLabel: title)
        }
    }
}

private struct ContactRow: View {
    @Binding var contact: SafetyContact
    let onRemove: () -> Void

    private var digits: String {
        contact.phone.filter { $0.isNumber || $0 == "+" }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Name", text: $contact.name)
                    .font(.system(.body, weight: .semibold))
                    .textContentType(.name)
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(contact.name.isEmpty ? "person" : contact.name)")
            }
            HStack {
                TextField("Phone number", text: $contact.phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                if !digits.isEmpty, let call = URL(string: "tel:\(digits)"), let text = URL(string: "sms:\(digits)") {
                    Link(destination: call) { Image(systemName: "phone.fill") }
                        .accessibilityLabel("Call \(contact.name)")
                        .frame(width: 44, height: 44)
                    Link(destination: text) { Image(systemName: "message.fill") }
                        .accessibilityLabel("Text \(contact.name)")
                        .frame(width: 44, height: 44)
                }
            }
            .font(.flowBody)
        }
        .padding(14)
        .card()
    }
}

/// One-time note before the skills toolkit is first used.
struct SkillsOnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "leaf")
                .font(.system(size: 30, weight: .light))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text("A toolkit for working through things")
                    .font(.flowTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("Locus offers short exercises drawn from CBT, DBT, and ACT. It's a self-help skills tool, not therapy, and it isn't a replacement for professional care.")
                    .font(.flowBody)
                    .foregroundStyle(Ink.primary.opacity(0.8))
                Text("You do the thinking; the app asks questions and keeps track. Everything stays on this device.")
                    .font(.flowBody)
                    .foregroundStyle(Ink.primary.opacity(0.8))
            }
            Link(destination: TherapyCatalog.findTherapistURL) {
                Label("Find a therapist", systemImage: "arrow.up.right.square")
                    .font(.flowButton)
            }
            Spacer()
            PrimaryButton(title: "Got it", action: onDone)
        }
        .padding(24)
        .background(Color.white)
        .interactiveDismissDisabled()
    }
}
