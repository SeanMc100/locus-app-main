import SwiftUI

/// Tinder-style sorting: swipe right for "in my control", left for "not".
struct SortCardsView: View {
    let items: [String]
    let onBack: () -> Void
    let onComplete: (_ inControl: [String], _ notInControl: [String]) -> Void

    @State private var index = 0
    @State private var decisions: [Bool] = []   // true = in my control
    @State private var offset: CGSize = .zero
    @State private var isAnimating = false
    @State private var haptic = 0

    private let threshold: CGFloat = 110

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.horizontal, 24)
                .padding(.top, 8)

            Text("Is this within your control?")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 28)

            ZStack {
                if index + 1 < items.count {
                    card(text: items[index + 1], dragX: 0)
                        .scaleEffect(0.94 + 0.06 * min(abs(offset.width) / threshold, 1))
                        .opacity(0.6)
                }
                if index < items.count {
                    card(text: items[index], dragX: offset.width)
                        .offset(x: offset.width, y: offset.height * 0.3)
                        .rotationEffect(.degrees(Double(offset.width / 22)))
                        .gesture(drag)
                        .id(index)
                }
            }
            .padding(.horizontal, 28)
            .frame(maxHeight: .infinity)

            buttons
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .background(Color.white)
        .sensoryFeedback(.impact(weight: .light), trigger: haptic)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onBack()
                } label: {
                    Label("Edit items", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                    .disabled(index == 0 || isAnimating)
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.08))
                    Capsule().fill(.black)
                        .frame(width: geo.size.width * CGFloat(index) / CGFloat(max(items.count, 1)))
                }
            }
            .frame(height: 4)
            .animation(.easeOut(duration: 0.25), value: index)

            Text("\(min(index + 1, items.count)) of \(items.count)")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.black.opacity(0.45))
        }
    }

    private func card(text: String, dragX: CGFloat) -> some View {
        let strength = min(abs(dragX) / threshold, 1)
        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.black.opacity(0.08 + 0.8 * strength), lineWidth: 1 + strength)

            Text(text)
                .font(.system(size: 24, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.black)
                .minimumScaleFactor(0.6)
                .padding(28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .overlay(alignment: .topLeading) {
            tag("IN MY CONTROL", filled: true)
                .rotationEffect(.degrees(-8))
                .padding(22)
                .opacity(dragX > 0 ? strength : 0)
        }
        .overlay(alignment: .topTrailing) {
            tag("NOT IN MY CONTROL", filled: false)
                .rotationEffect(.degrees(8))
                .padding(22)
                .opacity(dragX < 0 ? strength : 0)
        }
    }

    private func tag(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .heavy))
            .tracking(1)
            .foregroundStyle(filled ? .white : .black)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(filled ? .black : .white)
            )
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.black, lineWidth: 2))
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button {
                decide(false)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Not in my control")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.black, lineWidth: 1.5)
                )
            }
            Button {
                decide(true)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                    Text("In my control")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black))
            }
        }
        .disabled(isAnimating || index >= items.count)
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isAnimating else { return }
                offset = value.translation
            }
            .onEnded { value in
                guard !isAnimating else { return }
                let projected = value.predictedEndTranslation.width
                if value.translation.width > threshold || projected > threshold * 2.5 {
                    decide(true)
                } else if value.translation.width < -threshold || projected < -threshold * 2.5 {
                    decide(false)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { offset = .zero }
                }
            }
    }

    private func decide(_ inControl: Bool) {
        guard !isAnimating, index < items.count else { return }
        isAnimating = true
        haptic += 1
        withAnimation(.easeOut(duration: 0.25)) {
            offset = CGSize(width: inControl ? 600 : -600, height: offset.height)
        } completion: {
            decisions.append(inControl)
            offset = .zero
            index += 1
            isAnimating = false
            if index >= items.count { finish() }
        }
    }

    private func undo() {
        guard index > 0, !isAnimating else { return }
        decisions.removeLast()
        index -= 1
        haptic += 1
    }

    private func finish() {
        let pairs = zip(items, decisions)
        onComplete(pairs.filter { $0.1 }.map(\.0), pairs.filter { !$0.1 }.map(\.0))
    }
}
