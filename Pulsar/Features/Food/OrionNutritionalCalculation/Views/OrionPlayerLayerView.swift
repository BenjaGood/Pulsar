//
//  OrionPlayerLayerView.swift
//  Pulsar
//

import AVFoundation
import SwiftUI

struct OrionPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> OrionPlayerLayerContainerView {
        let view = OrionPlayerLayerContainerView()
        view.player = player
        return view
    }

    func updateUIView(_ view: OrionPlayerLayerContainerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }

    static func dismantleUIView(
        _ view: OrionPlayerLayerContainerView,
        coordinator: Void
    ) {
        view.player = nil
    }
}
