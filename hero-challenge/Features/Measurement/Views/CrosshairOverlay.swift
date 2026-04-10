import SwiftUI

/// Crosshair overlay for the AR camera view.
/// Changes color to green when the crosshair is near the first point (snap-to-close).
struct CrosshairOverlay: View {
    let controller: MeasureController

    private var isSnapping: Bool { controller.isNearFirstPoint }

    var body: some View {
        ZStack {
            Circle()
                .stroke(isSnapping ? Color.green : Color.white, lineWidth: 2.5)
                .frame(width: 90, height: 90)

            Circle()
                .fill(isSnapping ? Color.green : Color.white)
                .frame(width: 6, height: 6)
        }
        .opacity(controller.isSurfaceDetected ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: controller.isSurfaceDetected)
        .animation(.easeInOut(duration: 0.15), value: isSnapping)
    }
}
