//
//  SoundscapeModels.swift
//  Pulsar
//

import Foundation

enum SoundscapeCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case rain
    case forest
    case ocean
    case river
    case wind
    case fire
    case night
    case storm
    case ambient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rain: "Rain"
        case .forest: "Forest"
        case .ocean: "Ocean"
        case .river: "River"
        case .wind: "Wind"
        case .fire: "Fire"
        case .night: "Night"
        case .storm: "Storm"
        case .ambient: "Ambient"
        }
    }

    var symbolName: String {
        switch self {
        case .rain: "cloud.rain.fill"
        case .forest: "tree.fill"
        case .ocean: "water.waves"
        case .river: "drop.fill"
        case .wind: "wind"
        case .fire: "flame.fill"
        case .night: "moon.stars.fill"
        case .storm: "cloud.bolt.rain.fill"
        case .ambient: "waveform"
        }
    }
}

struct SoundscapeLayer: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var localFileName: String
    var volume: Float
    var loop: Bool
    var delaySeconds: Double?
    var randomizeStartTime: Bool
}

struct Soundscape: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var category: SoundscapeCategory
    var localFileName: String
    var remoteURL: URL?
    var durationSeconds: Int
    var isLoopable: Bool
    var isDownloaded: Bool
    var isPremium: Bool
    var license: String
    var sourceName: String
    var sourceURL: String
    var attributionRequired: Bool
    var attributionText: String?
    var commercialUseAllowed: Bool
    var layers: [SoundscapeLayer]

    var durationText: String {
        TimeInterval(durationSeconds).pulsarMindfulnessDurationText
    }

    var isComingSoon: Bool {
        !isDownloaded || localFileName.isEmpty
    }
}

struct SoundscapeLicense: Identifiable, Codable, Hashable {
    var id: String
    var fileName: String
    var title: String
    var sourceName: String
    var sourceURL: String
    var authorName: String
    var license: String
    var licenseURL: String
    var attributionRequired: Bool
    var attributionText: String?
    var commercialUseAllowed: Bool
    var downloadedAt: String
    var notes: String
}
