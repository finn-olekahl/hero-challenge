import SwiftUI

/// Main recording screen – the AI-Modus camera view with all controls.
struct RecordingView: View {
    var controller: RecordingController
    var onStopRecording: () -> Void
    var onCancel: () -> Void

    @State private var showMeasureMode = false

    var body: some View {
        ZStack {
            #if os(iOS)
            ARMeasureView(
                controller: controller.measureController,
                onPhotoCaptured: { image in
                    controller.capturePhoto(image)
                }
            )
            .ignoresSafeArea()
            #else
            Color.black.ignoresSafeArea()
            #endif

            if showMeasureMode {
                CrosshairOverlay(controller: controller.measureController)
            }

            recordingOverlay
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .task {
            await controller.startRecording()
        }
        .onChange(of: controller.state) { _, newState in
            if newState == .processing {
                onStopRecording()
            }
        }
        .alert("Fehler", isPresented: .init(
            get: { controller.hasError },
            set: { if !$0 { controller.clearError() } }
        )) {
            Button("OK") { controller.clearError() }
        } message: {
            Text(controller.errorMessage ?? "")
        }
    }

    // MARK: - Recording Overlay

    private var recordingOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            transcriptBar
            bottomControls
        }
        .padding(.top, 8)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Cancel
            Button { onCancel() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.4), in: Circle())
            }

            Spacer()

            // Recording indicator
            if controller.isActive {
                HStack(spacing: 8) {
                    Circle()
                        .fill(controller.state == .recording ? Color.red : Color.yellow)
                        .frame(width: 10, height: 10)

                    Text(controller.formattedElapsedTime)
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.55), in: Capsule())
            }

            Spacer()

            // Stats
            HStack(spacing: 12) {
                Label("\(controller.photoCount)", systemImage: "photo")
                Label("\(controller.measurementCount)", systemImage: "ruler")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.4), in: Capsule())
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Transcript Bar

    private var transcriptBar: some View {
        Group {
            if !controller.currentTranscript.isEmpty {
                Text(controller.currentTranscript.suffix(120))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Live measurement display
            if showMeasureMode {
                if controller.measureController.isNearFirstPoint {
                    // Snap hint
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Tippe + um Fläche zu schließen")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.65), in: Capsule())
                } else if let live = controller.measureController.liveDistanceText {
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
            }

            // Main action row
            HStack(alignment: .center) {
                // Pause/Resume
                if controller.state == .recording {
                    Button { controller.pauseRecording() } label: {
                        Image(systemName: "pause.fill")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                } else if controller.state == .paused {
                    Button { controller.resumeRecording() } label: {
                        Image(systemName: "play.fill")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                } else {
                    Spacer().frame(width: 56)
                }

                Spacer()

                // Central button: Photo or Measure point
                if showMeasureMode {
                    // Measure add point / close polygon
                    let isSnap = controller.measureController.isNearFirstPoint
                    Button { controller.measureController.addPoint() } label: {
                        ZStack {
                            Circle()
                                .stroke(isSnap ? Color.green.opacity(0.8) : Color.white.opacity(0.6), lineWidth: 3)
                                .frame(width: 80, height: 80)
                            Circle()
                                .fill(isSnap ? Color.green.opacity(0.3) : Color.white.opacity(0.12))
                                .frame(width: 66, height: 66)
                            Image(systemName: isSnap ? "checkmark" : "plus")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(isSnap ? .green : .white)
                        }
                    }
                    .disabled(!controller.measureController.isSurfaceDetected)
                    .opacity(controller.measureController.isSurfaceDetected ? 1.0 : 0.4)
                } else {
                    // Photo capture
                    Button {
                        capturePhoto()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.5), lineWidth: 3)
                                .frame(width: 80, height: 80)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 66, height: 66)
                        }
                    }
                }

                Spacer()

                // Stop recording
                Button {
                    Task { await controller.stopRecording() }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.red.opacity(0.5), lineWidth: 2)
                            .frame(width: 56, height: 56)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red)
                            .frame(width: 28, height: 28)
                    }
                }
            }
            .padding(.horizontal, 28)

            // Mode tabs
            modeTabs
        }
        .padding(.bottom, 16)
    }

    // MARK: - Mode Tabs

    private var modeTabs: some View {
        HStack(spacing: 0) {
            modeTabButton(title: "Foto", systemImage: "camera", isSelected: !showMeasureMode) {
                showMeasureMode = false
            }
            modeTabButton(title: "Messen", systemImage: "ruler", isSelected: showMeasureMode) {
                showMeasureMode = true
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.35), in: Capsule())
    }

    private func modeTabButton(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    // MARK: - Helpers

    private func capturePhoto() {
        #if os(iOS)
        NotificationCenter.default.post(name: .capturePhoto, object: nil)
        #endif
    }
}

extension Notification.Name {
    static let capturePhoto = Notification.Name("capturePhoto")
}
