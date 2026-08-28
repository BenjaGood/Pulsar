//
//  NutritionActivityLoadingAnimation.swift
//  Pulsar
//

import Lottie
import SwiftUI

struct NutritionActivityLoadingAnimation: View {
    private static let animationName = "ActivitySummaryLoading"

    private static let animation: LottieAnimation? = {
        let bundledAnimation = LottieAnimation.named(
            animationName,
            bundle: .main,
            subdirectory: "Resources/Animations"
        ) ?? LottieAnimation.named(animationName, bundle: .main)

        assert(bundledAnimation != nil, "Missing bundled Activity Summary loading animation")
        return bundledAnimation
    }()

    var body: some View {
        LottieView(animation: Self.animation)
            .configure { animationView in
                animationView.backgroundBehavior = .pauseAndRestore
                animationView.backgroundColor = .clear
                animationView.contentMode = .scaleAspectFit
                animationView.clipsToBounds = false
                animationView.isUserInteractionEnabled = false
            }
            .looping()
            .resizable()
            .aspectRatio(contentMode: .fit)
            .accessibilityHidden(true)
    }
}
