//
//  OrionPlayerLayerContainerView.swift
//  Pulsar
//

import AVFoundation
import UIKit

final class OrionPlayerLayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureForTransparentPlayback()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureForTransparentPlayback()
    }

    private var playerLayer: AVPlayerLayer {
        guard let playerLayer = layer as? AVPlayerLayer else {
            fatalError("OrionPlayerLayerContainerView requires AVPlayerLayer")
        }
        return playerLayer
    }

    private func configureForTransparentPlayback() {
        isOpaque = false
        backgroundColor = .clear
        layer.isOpaque = false
        playerLayer.backgroundColor = UIColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspect
    }
}
