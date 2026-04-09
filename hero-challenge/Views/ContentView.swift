//
//  ContentView.swift
//  hero-challenge
//
//  Created by Finn on 09.04.26.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = MeasureViewModel()

    var body: some View {
        ZStack {
#if os(iOS)
            ARSceneView(viewModel: viewModel)
                .ignoresSafeArea()
#else
            Color.black.ignoresSafeArea()
            Text("AR is not supported on this platform.")
                .foregroundStyle(.secondary)
#endif
            CrosshairView(viewModel: viewModel)
            MeasureOverlayView(viewModel: viewModel)
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
    }
}

#Preview {
    ContentView()
}
