import SwiftUI

/// A reusable animated progress view with pulsing icon, recap stats, and phased progress rows.
/// Used during AI evaluation, auto-matching, and offer generation.
struct PhasedProgressView: View {
    let title: String
    let subtitle: String
    let icon: String
    let accentColor: Color
    let phases: [Phase]
    let recapStats: [RecapStat]
    /// When set to `true`, rapidly completes all remaining phases and calls `onAllPhasesComplete`.
    var isComplete: Bool = false
    /// Called after all phases have visually completed following an `isComplete = true` signal.
    var onAllPhasesComplete: (() -> Void)? = nil

    @State private var visiblePhases: Int = 0
    @State private var completedPhases: Int = 0
    @State private var showRecap: Bool = false
    @State private var pulseAnimation: Bool = false

    struct Phase: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
    }

    struct RecapStat: Identifiable {
        let id = UUID()
        let icon: String
        let value: String
        let label: String
    }

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

                if showRecap, !recapStats.isEmpty {
                    recapCard
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                }

                VStack(spacing: 0) {
                    ForEach(Array(phases.enumerated()), id: \.element.id) { index, phase in
                        if index < visiblePhases {
                            phaseRow(phase: phase, index: index)
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
        .onChange(of: isComplete) { _, complete in
            if complete {
                completeAllPhasesAndFinish()
            }
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

    // MARK: - Recap Card

    private var recapCard: some View {
        HStack(spacing: 16) {
            ForEach(Array(recapStats.enumerated()), id: \.element.id) { index, stat in
                if index > 0 {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1, height: 36)
                }
                recapStatView(stat)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func recapStatView(_ stat: RecapStat) -> some View {
        VStack(spacing: 4) {
            Image(systemName: stat.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(accentColor)
            Text(stat.value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(stat.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Phase Row

    private func phaseRow(phase: Phase, index: Int) -> some View {
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
                    Image(systemName: phase.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 26, height: 26)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: completedPhases)

            Text(phase.label)
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

        // Auto-complete early phases on a schedule to give visual feedback
        // while the actual work proceeds. Each phase auto-completes 1.5s after
        // it first appears, up to (phases.count - 2) to leave the final phases
        // for the real completion signal.
        let maxAutoComplete = max(0, phases.count - 2)
        for i in 0..<maxAutoComplete {
            let delay = 1.8 + Double(i) * 1.7
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation { completedPhases = max(completedPhases, i + 1) }
            }
        }
    }

    private func completeAllPhasesAndFinish() {
        let remaining = phases.count - completedPhases
        for i in 0..<remaining {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    completedPhases = min(completedPhases + 1, phases.count)
                }
            }
        }

        let navigationDelay = Double(remaining) * 0.3 + 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + navigationDelay) {
            onAllPhasesComplete?()
        }
    }
}

