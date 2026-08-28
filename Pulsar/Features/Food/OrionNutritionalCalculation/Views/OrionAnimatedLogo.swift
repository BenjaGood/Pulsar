//
//  OrionAnimatedLogo.swift
//  Pulsar
//

import SwiftUI

struct OrionAnimatedLogo: View {
    private static let mediaCanvasScale: CGFloat = 1.9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var playbackController = OrionAnimatedLogoPlaybackController()

    var size: CGFloat = 104

    var body: some View {
        Group {
            if reduceMotion {
                Image("OrionMonochromeFirstFrame")
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ZStack {
                    Image("OrionMonochromeFirstFrame")
                        .renderingMode(.original)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .opacity(playbackController.isReady ? 0 : 1)

                    OrionPlayerLayerView(player: playbackController.player)
                        .opacity(playbackController.isReady ? 1 : 0)
                }
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.01)
                        : .easeOut(duration: 0.16),
                    value: playbackController.isReady
                )
            }
        }
        .frame(
            width: size * Self.mediaCanvasScale,
            height: size * Self.mediaCanvasScale
        )
        .frame(width: size, height: size)
        .clipped()
        .accessibilityHidden(true)
        .onAppear {
            playbackController.updatePresentationState(
                isVisible: true,
                reduceMotion: reduceMotion,
                sceneIsActive: scenePhase == .active
            )
        }
        .onDisappear {
            playbackController.setVisible(false)
        }
        .onChange(of: reduceMotion) { _, newValue in
            playbackController.setReduceMotion(newValue)
        }
        .onChange(of: scenePhase) { _, newValue in
            playbackController.setSceneActive(newValue == .active)
        }
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            await playbackController.prepareIfNeeded()
        }
    }
}

#Preview {
    OrionAnimatedLogo(size: 104)
        .padding(24)
        .background(.white)
}
