import SwiftUI

struct MealScannerIntroView: View {
    var isLiDARReady: Bool
    var isStarting: Bool
    var errorMessage: String?
    var onStart: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            let usableHeight = proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom
            let isCompact = usableHeight < 700
            let horizontalPadding: CGFloat = proxy.size.width < 390 ? 16 : 22
            let viewportHeight = min(
                isCompact ? 286 : 350,
                max(isCompact ? 232 : 300, usableHeight * 0.42)
            )
            let content = VStack(spacing: 0) {
                MealScannerIntroHeader(
                    isLiDARReady: isLiDARReady,
                    isCompact: isCompact
                )

                MealScannerIntroViewport(isLiDARReady: isLiDARReady)
                    .frame(height: viewportHeight)
                    .padding(.top, isCompact ? 20 : 26)
                    .layoutPriority(1)

                MealScannerInfoSection(isCompact: isCompact)
                    .padding(.top, isCompact ? 16 : 22)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .pulsarTextStyle(.metadata)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pulsarLiquidGlass(cornerRadius: 16, isClear: true)
                        .padding(.top, 12)
                }

                Spacer(minLength: isCompact ? 14 : 18)

                MealScannerStartButton(
                    isStarting: isStarting,
                    action: onStart
                )
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, isCompact ? 18 : 24)
            .padding(.bottom, max(proxy.safeAreaInsets.bottom, isCompact ? 16 : 22))
            .frame(minHeight: proxy.size.height, alignment: .top)

            ZStack {
                NutritionDesign.pageBackground
                    .ignoresSafeArea()

                PulsarGlassEffectGroup(spacing: isCompact ? 8 : 12) {
                    if dynamicTypeSize.isAccessibilitySize {
                        ScrollView {
                            content
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                    } else {
                        content
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .tint(.black)
    }
}

#Preview("Meal Scanner — Pro", traits: .fixedLayout(width: 393, height: 852)) {
    MealScannerIntroView(
        isLiDARReady: true,
        isStarting: false,
        errorMessage: nil,
        onStart: {}
    )
}

#Preview("Meal Scanner — Pro Max", traits: .fixedLayout(width: 430, height: 932)) {
    MealScannerIntroView(
        isLiDARReady: true,
        isStarting: false,
        errorMessage: nil,
        onStart: {}
    )
}
