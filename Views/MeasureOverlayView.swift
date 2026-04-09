//
//  MeasureOverlayView.swift
//  hero-challenge
//

import SwiftUI

/// HUD overlay that replicates the iOS Measure app controls.
struct MeasureOverlayView: View {
    let viewModel: MeasureViewModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomArea
        }
        .padding(.top, 8)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            // List button
            Button { } label: {
                Image(systemName: "list.bullet")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.4), in: Circle())
            }

            Spacer()

            // Trash / clear button
            if viewModel.canClear {
                Button { viewModel.clear() } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.black.opacity(0.4), in: Circle())
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Bottom area

    private var bottomArea: some View {
        VStack(spacing: 16) {
            // Live distance label with directional chevron
            if let live = viewModel.liveDistanceText {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .heavy))
                    Text(live)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.55), in: Capsule())
            }

            // Action buttons row
            HStack(alignment: .center) {
                // Undo
                Button { viewModel.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .opacity(viewModel.canUndo ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: viewModel.canUndo)

                Spacer()

                // Add point
                Button { viewModel.addPoint() } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 3)
                            .frame(width: 80, height: 80)
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 66, height: 66)
                        Image(systemName: "plus")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(!viewModel.isSurfaceDetected)
                .opacity(viewModel.isSurfaceDetected ? 1.0 : 0.4)
                .animation(.easeInOut(duration: 0.15), value: viewModel.isSurfaceDetected)

                Spacer()

                // Capture / screenshot
                Button { } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.4), lineWidth: 2)
                            .frame(width: 56, height: 56)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 46, height: 46)
                    }
                }
            }
            .padding(.horizontal, 28)

            // Measure / Level tabs
            measureLevelTabs
        }
        .padding(.bottom, 16)
    }

    // MARK: - Tabs

    private var measureLevelTabs: some View {
        HStack(spacing: 0) {
            tabButton(title: "Measure", systemImage: "ruler", isSelected: true)
            tabButton(title: "Level", systemImage: "level", isSelected: false)
        }
        .padding(4)
        .background(Color.black.opacity(0.35), in: Capsule())
    }

    private func tabButton(title: String, systemImage: String, isSelected: Bool) -> some View {
        Button { } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.medium))
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.45))
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white.opacity(0.15) : Color.clear, in: Capsule())
        }
    }
}
