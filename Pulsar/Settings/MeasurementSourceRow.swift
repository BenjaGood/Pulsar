//
//  MeasurementSourceRow.swift
//  Pulsar
//

import SwiftUI

struct MeasurementSourceRow: View {
    var source: ProfileValueSource
    var caption: String
    var menuSectionTitle = "All Measurements"
    var selectSource: (ProfileValueSource) -> Void
    var selectHeightSource: ((ProfileValueSource) -> Void)? = nil
    var selectWeightSource: ((ProfileValueSource) -> Void)? = nil

    var body: some View {
        Menu {
            Section(menuSectionTitle) {
                MeasurementSourceMenuOptions(
                    selectedSource: source,
                    selectSource: selectSource
                )
            }

            if let selectHeightSource, let selectWeightSource {
                Section("Height") {
                    MeasurementSourceMenuOptions(
                        selectedSource: source,
                        selectSource: selectHeightSource
                    )
                }

                Section("Weight") {
                    MeasurementSourceMenuOptions(
                        selectedSource: source,
                        selectSource: selectWeightSource
                    )
                }
            }
        } label: {
            MeasurementSourceRowLabel(
                source: source,
                caption: caption,
                symbol: sourceSymbol
            )
        }
        .buttonStyle(MeasurementPressButtonStyle(pressedScale: 0.985))
        .accessibilityHint("Opens measurement source choices")
    }

    private var sourceSymbol: String {
        symbol(for: source)
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
