import SwiftUI

// MARK: - Phased Progress View

/// A reusable animated progress screen that shows pulsing rings, a recap card,
/// and staggered phase rows with checkmark/spinner/icon states.
///
/// Used for AI evaluation processing, offer generation, and auto-matching.
struct PhasedProgressView<RecapContent: View>: View {
    let accentColor: Color
    let icon: String
    let title: String
    let subtitle: String
    let phases: [ProgressPhase]
    let completedPhases: Int
    @ViewBuilder let recapContent: () -> RecapContent

    @State private var pulseAnimation = false
    @State private var visiblePhases = 0
    @State private var showRecap = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), accentColor.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 40)

                pulsingIcon
                    .padding(.bottom, 28)

                Text(title)
                    .font(.title2.weight(.bold))
                    .padding(.bottom, 6)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 32)

                if showRecap {
                    recapContent()
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                }

                VStack(spacing: 0) {
                    ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                        if index < visiblePhases {
                            PhaseRow(
                                icon: phase.icon,
                                label: phase.label,
                                index: index,
                                completedPhases: completedPhases,
                                accentColor: accentColor
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .onAppear {
            pulseAnimation = true
            startPhaseAnimations()
        }
    }

    // MARK: - Pulsing Icon

    private var pulsingIcon: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(accentColor.opacity(0.15 - Double(i) * 0.04), lineWidth: 1.5)
                    .frame(width: CGFloat(80 + i * 28), height: CGFloat(80 + i * 28))
                    .scaleEffect(pulseAnimation ? 1.08 : 0.95)
                    .animation(
                        .easeInOut(duration: 1.8)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.3),
                        value: pulseAnimation
                    )
            }

            Image(systemName: icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(accentColor)
                .frame(width: 72, height: 72)
                .background(accentColor.opacity(0.1), in: Circle())
        }
    }

    // MARK: - Animation Logic

    private func startPhaseAnimations() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showRecap = true
            }
        }

        for i in 0..<phases.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + Double(i) * 0.4) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    visiblePhases = i + 1
                }
            }
        }
    }
}

// MARK: - Progress Phase

struct ProgressPhase {
    let icon: String
    let label: String
}

// MARK: - Phase Row

/// A single row in a phased progress display showing icon/spinner/checkmark state.
private struct PhaseRow: View {
    let icon: String
    let label: String
    let index: Int
    let completedPhases: Int
    let accentColor: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if index < completedPhases {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else if index == completedPhases {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(accentColor)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 26, height: 26)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: completedPhases)

            Text(label)
                .font(.subheadline.weight(index <= completedPhases ? .medium : .regular))
                .foregroundStyle(index <= completedPhases ? .primary : .tertiary)

            Spacer()

            if index < completedPhases {
                Text("Fertig")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.3), value: completedPhases)
    }
}
