import SwiftUI

struct WatchLaunchAnimationView: View {
    var onCompletion: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasStarted = false
    @State private var logoOpacity = 0.0
    @State private var logoScale = 0.94
    @State private var containerOpacity = 1.0

    private static let markAspectRatio: CGFloat = 846.0 / 720.0

    var body: some View {
        GeometryReader { proxy in
            let markHeight = preferredMarkHeight(in: proxy.size)
            let markWidth = markHeight * Self.markAspectRatio

            ZStack {
                background

                Image(logoAssetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .id(logoAssetName)
                    .frame(width: markWidth, height: markHeight)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity * containerOpacity)
                    .accessibilityLabel("Pulsar")
            }
        }
        .task { await playIfNeeded() }
    }

    private var logoAssetName: String {
        colorScheme == .dark ? "PulsarLogoDark" : "PulsarLogoLight"
    }

    private var background: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            Circle()
                .fill(Color.red.opacity(colorScheme == .dark ? 0.13 : 0.08))
                .blur(radius: 28)
                .frame(width: 96, height: 96)
                .opacity(logoOpacity)
        }
    }

    private func preferredMarkHeight(in size: CGSize) -> CGFloat {
        min(size.width * 0.42, size.height * 0.24)
    }

    private func playIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

        if reduceMotion {
            logoOpacity = 1
            logoScale = 1
            try? await Task.sleep(for: .milliseconds(500))
            containerOpacity = 0
            onCompletion()
            return
        }

        withAnimation(.smooth(duration: 0.46)) {
            logoOpacity = 1
            logoScale = 1
        }

        try? await Task.sleep(for: .milliseconds(850))

        withAnimation(.easeInOut(duration: 0.28)) {
            containerOpacity = 0
        }

        try? await Task.sleep(for: .milliseconds(280))
        onCompletion()
    }
}
