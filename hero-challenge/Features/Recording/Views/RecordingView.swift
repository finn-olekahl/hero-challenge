import SwiftUI

/// Main recording screen – the AI-Modus camera view with all controls.
struct RecordingView: View {
    var controller: RecordingController
    var onStopRecording: () -> Void
    var onCancel: () -> Void

    @State private var showMeasureMode = false
    @State private var showPhotoFlash = false

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

            // Only show crosshair when actively measuring
            if showMeasureMode && controller.measureController.phase == .measuring {
                CrosshairOverlay(controller: controller.measureController)
            }

            recordingOverlay

            // Photo flash overlay
            if showPhotoFlash {
                Color.white
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
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
        .onChange(of: showMeasureMode) { _, isMeasure in
            if isMeasure && controller.measureController.phase != .measuring {
                // When switching to measure tab, show type picker
                controller.measureController.startNewMeasurement()
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
            // Measurement info bar
            if showMeasureMode {
                measureInfoBar
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

                // Central button: depends on mode + phase
                centralButton

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

    // MARK: - Central Button

    @ViewBuilder
    private var centralButton: some View {
        if showMeasureMode {
            switch controller.measureController.phase {
            case .choosingType:
                // Type picker replaces the button
                measureTypePicker

            case .measuring:
                // Add point / close polygon
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

            case .completed:
                // New measurement button
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        controller.measureController.startNewMeasurement()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.teal.opacity(0.6), lineWidth: 3)
                            .frame(width: 80, height: 80)
                        Circle()
                            .fill(Color.teal.opacity(0.15))
                            .frame(width: 66, height: 66)
                        Image(systemName: "plus.viewfinder")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.teal)
                    }
                }
            }
        } else {
            // Photo capture
            Button {
                capturePhotoWithFlash()
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
    }

    // MARK: - Measure Type Picker

    private var measureTypePicker: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    controller.measureController.selectMode(.distance)
                }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 22, weight: .medium))
                    Text("Strecke")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    controller.measureController.selectMode(.area)
                }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 22, weight: .medium))
                    Text("Fläche")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Measure Info Bar

    @ViewBuilder
    private var measureInfoBar: some View {
        let mc = controller.measureController
        switch mc.phase {
        case .choosingType:
            Text("Messtyp wählen")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.45), in: Capsule())

        case .measuring:
            if mc.isNearFirstPoint {
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
            } else if let live = mc.liveDistanceText {
                HStack(spacing: 4) {
                    Image(systemName: mc.measurementMode == .distance ? "arrow.left.and.right" : "square.dashed")
                        .font(.system(size: 10, weight: .heavy))
                    Text(live)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.55), in: Capsule())
            } else if mc.placedPoints.isEmpty {
                let hint = mc.measurementMode == .distance ? "Startpunkt setzen" : "Ersten Eckpunkt setzen"
                Text(hint)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.45), in: Capsule())
            }

        case .completed:
            if let result = mc.completedResultText {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text(result)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.teal.opacity(0.7), in: Capsule())
            }
        }
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

    private func capturePhotoWithFlash() {
        #if os(iOS)
        // Trigger flash
        withAnimation(.easeIn(duration: 0.05)) {
            showPhotoFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.25)) {
                showPhotoFlash = false
            }
        }
        // Capture
        NotificationCenter.default.post(name: .capturePhoto, object: nil)
        #endif
    }
}

extension Notification.Name {
    static let capturePhoto = Notification.Name("capturePhoto")
}
