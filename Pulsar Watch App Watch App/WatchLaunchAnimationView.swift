import SwiftUI

struct WatchLaunchAnimationView: View {
    var onCompletion: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasStarted = false
    @State private var logoOpacity = 0.0
    @State private var logoScale = 0.94
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
            let entryTravel = min(proxy.size.width * 0.15, max(10, markHeight * 0.62))

            ZStack {
                background

                ZStack {
                    Image(leftAssetName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .id(leftAssetName)
                        .frame(width: leftWidth, height: markHeight)
                        .offset(
                            x: finalMarkOffset * progress - markWidth / 2 - leftSpacing - leftWidth / 2 - entryTravel * (1 - progress)
                        )
                        .blur(radius: (1 - progress) * 2.2)
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
                        .offset(
                            x: finalMarkOffset * progress + markWidth / 2 + rightSpacing + rightWidth / 2 + entryTravel * (1 - progress)
                        )
                        .blur(radius: (1 - progress) * 2.2)
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
        (colorScheme == .dark ? Color.black : Color.white)
            .ignoresSafeArea()
    }

    private func preferredMarkHeight(in size: CGSize) -> CGFloat {
        let totalAspect = Self.leftAspectRatio + Self.leftSpacingRatio + Self.markAspectRatio + Self.rightSpacingRatio + Self.rightAspectRatio
        let widthBound = size.width * 0.84
        let heightBound = size.height * 0.19
        return max(28, min(widthBound / totalAspect, heightBound, 54))
    }

    private func playIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

        if reduceMotion {
            logoOpacity = 1
            logoScale = 1
            wordmarkProgress = 1
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

        withAnimation(.smooth(duration: 0.58)) {
            wordmarkProgress = 1
        }

        try? await Task.sleep(for: .milliseconds(620))

        withAnimation(.easeInOut(duration: 0.28)) {
            containerOpacity = 0
        }

        try? await Task.sleep(for: .milliseconds(280))
        onCompletion()
    }
}
