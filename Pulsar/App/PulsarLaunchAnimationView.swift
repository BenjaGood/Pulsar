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
    @State private var wordmarkProgress: CGFloat = 0
    @State private var containerOpacity = 1.0

    private static let markAspectRatio: CGFloat = 628.0 / 1024.0
    private static let leftAspectRatio: CGFloat = 1538.0 / 1024.0
    private static let rightAspectRatio: CGFloat = 1133.0 / 1024.0
    private static let leftSpacingRatio: CGFloat = 0.104
    private static let rightSpacingRatio: CGFloat = 0.136

    var body: some View {
        GeometryReader { proxy in
            let markHeight = preferredMarkHeight(in: proxy.size)
            let markWidth = markHeight * Self.markAspectRatio
            let leftWidth = markHeight * Self.leftAspectRatio
            let rightWidth = markHeight * Self.rightAspectRatio
            let leftSpacing = markHeight * Self.leftSpacingRatio
            let rightSpacing = markHeight * Self.rightSpacingRatio
            let totalWidth = leftWidth + leftSpacing + markWidth + rightSpacing + rightWidth
            let finalMarkOffset = (leftWidth + leftSpacing - rightWidth - rightSpacing) / 2
            let progress = max(0, min(wordmarkProgress, 1))
            let entryTravel = min(proxy.size.width * 0.14, max(18, markHeight * 0.74))

            ZStack {
                background

                ZStack {
                    Image(leftAssetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .id(leftAssetName)
                        .frame(width: leftWidth, height: markHeight)
                        .scaleEffect(0.985 + 0.015 * progress, anchor: .trailing)
                        .offset(
                            x: finalMarkOffset * progress - markWidth / 2 - leftSpacing - leftWidth / 2 - entryTravel * (1 - progress)
                        )
                        .blur(radius: (1 - progress) * 3.5)
                        .opacity(Double(progress))

                    Image(logoAssetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .id(logoAssetName)
                        .frame(width: markWidth, height: markHeight)
                        .offset(x: finalMarkOffset * progress)

                    Image(rightAssetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .id(rightAssetName)
                        .frame(width: rightWidth, height: markHeight)
                        .scaleEffect(0.985 + 0.015 * progress, anchor: .leading)
                        .offset(
                            x: finalMarkOffset * progress + markWidth / 2 + rightSpacing + rightWidth / 2 + entryTravel * (1 - progress)
                        )
                        .blur(radius: (1 - progress) * 3.5)
                        .opacity(Double(progress))
                }
                .frame(width: totalWidth, height: markHeight)
                .scaleEffect(logoScale)
                .opacity(logoOpacity * containerOpacity)
                .accessibilityLabel("Pulsar")
            }
        }
        .task { await playIfNeeded() }
    }

    private var logoAssetName: String {
        colorScheme == .dark ? "PulsarLogoDark" : "PulsarLogo"
    }

    private var leftAssetName: String {
        colorScheme == .dark ? "PulsarWordmarkLeftDark" : "PulsarWordmarkLeft"
    }

    private var rightAssetName: String {
        colorScheme == .dark ? "PulsarWordmarkRightDark" : "PulsarWordmarkRight"
    }

    private var background: some View {
        Color(uiColor: colorScheme == .dark ? .black : .systemBackground)
            .ignoresSafeArea()
    }

    private func preferredMarkHeight(in size: CGSize) -> CGFloat {
        let totalAspect = Self.leftAspectRatio + Self.leftSpacingRatio + Self.markAspectRatio + Self.rightSpacingRatio + Self.rightAspectRatio
        let widthBound = min(size.width * 0.86, 620)
        let heightBound = size.height * 0.14
        return max(42, min(widthBound / totalAspect, heightBound, 132))
    }

    private func playIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

        if reduceMotion {
            logoOpacity = 1
            logoScale = 1
            wordmarkProgress = 1
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

        withAnimation(.smooth(duration: 0.82)) {
            wordmarkProgress = 1
        }

        try? await Task.sleep(for: .milliseconds(1_060))

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
