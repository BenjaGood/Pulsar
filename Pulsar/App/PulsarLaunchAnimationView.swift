import SwiftUI

struct PulsarLaunchContainer<Content: View>: View {
    @State private var isShowingLaunch = true
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .opacity(isShowingLaunch ? 0 : 1)
                .animation(.easeOut(duration: 0.36), value: isShowingLaunch)

            if isShowingLaunch {
                PulsarLaunchAnimationView {
                    withAnimation(.easeInOut(duration: 0.34)) {
                        isShowingLaunch = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
                .allowsHitTesting(false)
            }
        }
    }
}

struct PulsarLaunchAnimationView: View {
    var onCompletion: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasStarted = false
    @State private var logoOpacity = 0.0
    @State private var logoScale = 0.96
    @State private var revealProgress: CGFloat = 0
    @State private var containerOpacity = 1.0

    private static let markAspectRatio: CGFloat = 846.0 / 720.0
    private static let tailAspectRatio: CGFloat = 3381.0 / 720.0

    var body: some View {
        GeometryReader { proxy in
            let markHeight = preferredMarkHeight(in: proxy.size)
            let markWidth = markHeight * Self.markAspectRatio
            let tailWidth = markHeight * Self.tailAspectRatio

            ZStack {
                background

                HStack(alignment: .center, spacing: 0) {
                    Image(logoAssetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .id(logoAssetName)
                        .frame(width: markWidth, height: markHeight)

                    Image(tailAssetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .id(tailAssetName)
                        .frame(width: tailWidth, height: markHeight, alignment: .leading)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: max(0, tailWidth * revealProgress))
                        }
                }
                .frame(width: markWidth + tailWidth, height: markHeight)
                .offset(x: (tailWidth / 2) * (1 - revealProgress))
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

    private var tailAssetName: String {
        colorScheme == .dark ? "PulsarWordmarkTailDark" : "PulsarWordmarkTailLight"
    }

    private var background: some View {
        ZStack {
            Color(uiColor: colorScheme == .dark ? .black : .systemBackground)

            RadialGradient(
                colors: [
                    Color.red.opacity(colorScheme == .dark ? 0.12 : 0.08),
                    Color.clear
                ],
                center: .center,
                startRadius: 8,
                endRadius: 320
            )
            .scaleEffect(1 + revealProgress * 0.12)
            .opacity(logoOpacity)
        }
        .ignoresSafeArea()
    }

    private func preferredMarkHeight(in size: CGSize) -> CGFloat {
        let totalAspect = Self.markAspectRatio + Self.tailAspectRatio
        let widthBound = min(size.width * 0.86, 560)
        let heightBound = size.height * 0.14
        return max(42, min(widthBound / totalAspect, heightBound))
    }

    private func playIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

        if reduceMotion {
            logoOpacity = 1
            logoScale = 1
            revealProgress = 1
            try? await Task.sleep(for: .milliseconds(650))
            containerOpacity = 0
            onCompletion()
            return
        }

        withAnimation(.smooth(duration: 0.58)) {
            logoOpacity = 1
            logoScale = 1
        }

        try? await Task.sleep(for: .milliseconds(460))

        withAnimation(.smooth(duration: 0.92)) {
            revealProgress = 1
        }

        try? await Task.sleep(for: .milliseconds(1_120))

        withAnimation(.easeInOut(duration: 0.34)) {
            containerOpacity = 0
        }

        try? await Task.sleep(for: .milliseconds(340))
        onCompletion()
    }
}

#Preview("Launch Light") {
    PulsarLaunchAnimationView()
}

#Preview("Launch Dark") {
    PulsarLaunchAnimationView()
        .preferredColorScheme(.dark)
}
