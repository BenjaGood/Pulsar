//
//  PulsarSettingsBackground.swift
//  Pulsar
//

import SwiftUI

struct PulsarSettingsBackground: View {
    var body: some View {
        SettingsMonochromeDesign.pageBackground
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
