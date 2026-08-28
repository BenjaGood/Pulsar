//
//  MeasurementSourceMenuOptions.swift
//  Pulsar
//

import SwiftUI

struct MeasurementSourceMenuOptions: View {
    var selectedSource: ProfileValueSource
    var selectSource: (ProfileValueSource) -> Void

    var body: some View {
        ForEach(ProfileValueSource.allCases) { option in
            Button {
                selectSource(option)
            } label: {
                Label(
                    option.rawValue,
                    systemImage: option == selectedSource ? "checkmark" : symbol(for: option)
                )
            }
        }
    }

    private func symbol(for source: ProfileValueSource) -> String {
        switch source {
        case .healthKit:
            "heart.fill"
        case .manual:
            "pencil"
        }
    }
}
