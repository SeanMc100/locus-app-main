import SwiftUI
import SwiftData

/// Drafts and pending sessions, newest first; tap to pick up where you
/// left off.
struct InProgressSection: View {
    let onResume: (TherapySession) -> Void

    @Query(filter: #Predicate<TherapySession> { $0.statusRaw != "complete" && !$0.isPractice },
           sort: \TherapySession.updatedAt, order: .reverse)
    private var sessions: [TherapySession]

    var body: some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                CapsLabel("In progress")
                VStack(spacing: 10) {
                    ForEach(sessions) { session in
                        Button {
                            onResume(session)
                        } label: {
                            InProgressRow(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct InProgressRow: View {
    let session: TherapySession

    private var status: String {
        switch session.status {
        case .pending:
            if let when = session.scheduledAt, when > .now {
                return "Planned for \(when.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Ready to check in"
        case .draft:
            return session.stepTotal > 1 ? "Step \(session.stepPosition) of \(session.stepTotal)" : "Just started"
        case .complete:
            return "Done"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: session.tool.symbol)
                .font(.system(size: 18))
                .foregroundStyle(session.method.accent)
                .frame(width: 28)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.tool.title)
                    .font(.system(.body, weight: .semibold))
                if !session.targetThought.isEmpty {
                    Text("“\(session.targetThought)”")
                        .font(.flowHelper)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Text(status)
                    .font(.flowCaption.weight(.medium))
                    .foregroundStyle(session.status == .pending && (session.scheduledAt ?? .distantFuture) <= .now
                                     ? session.method.accent : Ink.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.tertiary)
                .padding(.top, 4)
        }
        .padding(16)
        .contentShape(Rectangle())
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Resume")
    }
}
