//
//  NutritionBackground.swift
//  Pulsar
//

import SwiftUI

struct NutritionBackground: View {
    var body: some View {
        GeometryReader { proxy in
            Image("NutritionBackground")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0),
                            Color.black.opacity(0.16)
                        ],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: proxy.size.height * 0.42)
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()
        }
    }
}

#Preview {
    NutritionBackground()
}
