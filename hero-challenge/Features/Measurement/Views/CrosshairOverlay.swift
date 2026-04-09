import SwiftUI

/// Crosshair overlay for the AR camera view.
struct CrosshairOverlay: View {
    let controller: MeasureController

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 2.5)
                .frame(width: 90, height: 90)

            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
        }
        .opacity(controller.isSurfaceDetected ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: controller.isSurfaceDetected)
    }
}
