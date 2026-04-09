//
//  CrosshairView.swift
//  hero-challenge
//

import SwiftUI

/// Large centred crosshair circle that mimics the iOS Measure app height mode.
struct CrosshairView: View {
    let viewModel: MeasureViewModel

    var body: some View {
        ZStack {
            // Large outer ring
            Circle()
                .stroke(Color.white, lineWidth: 2.5)
                .frame(width: 90, height: 90)

            // Inner dot
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
        }
        .opacity(viewModel.isSurfaceDetected ? 1.0 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSurfaceDetected)
    }
}
