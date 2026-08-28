import SwiftUI

private struct PulsarWorkoutMiniPlayerPreviewHost: View {
    @StateObject private var layoutController: PulsarBottomChromeLayoutController

    let state: PulsarWorkoutMiniPlayerState

    init(state: PulsarWorkoutMiniPlayerState, layout: PulsarBottomChromeBarLayout) {
        self.state = state
        let defaults = UserDefaults(suiteName: "PulsarWorkoutMiniPlayerPreview.\(UUID().uuidString)")!
        defaults.set(layout.rawValue, forKey: PulsarBottomChromeLayoutController.preferenceKey)
        _layoutController = StateObject(
            wrappedValue: PulsarBottomChromeLayoutController(defaults: defaults, playsHaptics: false)
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.8), .green.opacity(0.55), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            PulsarWorkoutMiniPlayerView(
                state: state,
                usesNativeAccessoryChrome: false,
                layoutController: layoutController,
                onOpen: {}
            )
            .padding(20)
        }
        .frame(height: 180)
    }
}

private extension PulsarWorkoutMiniPlayerState {
    static let previewRun = PulsarWorkoutMiniPlayerState(
        id: "preview-indoor-running",
        sessionID: UUID(),
        kind: .run(.indoorRunning),
        title: "Indoor Running",
        symbol: PulsarOutdoorWorkoutKind.indoorRunning.systemImageName,
        status: .live,
        elapsedText: "00:13",
        secondaryMetrics: [
            .init(kind: .heartRate, label: "Heart rate", value: "59 bpm"),
            .init(kind: .calories, label: "Energy", value: "12 kcal")
        ]
    )
}

#Preview("Expanded Run") {
    PulsarWorkoutMiniPlayerPreviewHost(state: .previewRun, layout: .expanded)
}

#Preview("Compact Run") {
    PulsarWorkoutMiniPlayerPreviewHost(state: .previewRun, layout: .compact)
}

