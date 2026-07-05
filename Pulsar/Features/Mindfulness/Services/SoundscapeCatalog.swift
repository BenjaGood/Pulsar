//
//  SoundscapeCatalog.swift
//  Pulsar
//

import Foundation

enum SoundscapeCatalog {
    static let bundledCore: [Soundscape] = [
        soundscape(
            id: "gentle-rain",
            title: "Gentle Rain",
            subtitle: "Soft rainfall with an even, loopable texture.",
            category: .rain,
            localFileName: "gentle_rain_loop.mp3",
            durationSeconds: 33,
            sourceName: "SoundBible",
            sourceURL: "https://soundbible.com/2011-Rain-Background.html",
            license: "Attribution 3.0",
            attributionRequired: true,
            attributionText: "Rain Background by Mike Koenig, SoundBible.com"
        ),
        soundscape(
            id: "ocean-waves",
            title: "Ocean Waves",
            subtitle: "Slow shoreline waves for spacious attention.",
            category: .ocean,
            localFileName: "ocean_waves_loop.mp3",
            durationSeconds: 68,
            sourceName: "SoundBible",
            sourceURL: "https://soundbible.com/1936-Crisp-Ocean-Waves.html",
            license: "Attribution 3.0",
            attributionRequired: true,
            attributionText: "Crisp Ocean Waves by Mike Koenig, SoundBible.com"
        ),
        soundscape(
            id: "forest-morning",
            title: "Forest Morning",
            subtitle: "Quiet forest bed without voices or music.",
            category: .forest,
            localFileName: "forest_morning_loop.mp3",
            durationSeconds: 36,
            sourceName: "SoundBible",
            sourceURL: "https://soundbible.com/1263-Nature-Ambiance.html",
            license: "Public Domain"
        ),
        soundscape(
            id: "mountain-stream",
            title: "Mountain Stream",
            subtitle: "Continuous water movement, calm and bright.",
            category: .river,
            localFileName: "mountain_stream_loop.mp3",
            durationSeconds: 13,
            sourceName: "SoundBible",
            sourceURL: "https://soundbible.com/2032-Water.html",
            license: "Public Domain"
        ),
        soundscape(
            id: "night-crickets",
            title: "Night Crickets",
            subtitle: "Soft night ambience for low-stimulation focus.",
            category: .night,
            localFileName: "night_crickets_loop.mp3",
            durationSeconds: 49,
            sourceName: "SoundBible",
            sourceURL: "https://soundbible.com/2083-Crickets-Chirping-At-Night.html",
            license: "Public Domain"
        ),
        soundscape(
            id: "fireplace",
            title: "Fireplace",
            subtitle: "Warm fire bed for winter recovery.",
            category: .fire,
            localFileName: "fireplace_loop.mp3",
            durationSeconds: 16,
            sourceName: "SoundBible",
            sourceURL: "https://soundbible.com/1902-Fire-Burning.html",
            license: "Attribution 3.0",
            attributionRequired: true,
            attributionText: "Fire Burning by JaBa, SoundBible.com"
        ),
        soundscape(
            id: "distant-storm",
            title: "Distant Storm",
            subtitle: "Low thunder far behind steady rain.",
            category: .storm,
            localFileName: "distant_storm_loop.mp3",
            durationSeconds: 13,
            sourceName: "SoundBible",
            sourceURL: "https://soundbible.com/886-Distant-Thunder-And-Light-Rain.html",
            license: "Attribution 3.0",
            attributionRequired: true,
            attributionText: "Distant Thunder And Light Rain from SoundBible.com"
        ),
        soundscape(
            id: "wind-through-trees",
            title: "Wind Through Trees",
            subtitle: "Layered wind through quiet branches.",
            category: .wind,
            localFileName: "wind_through_trees_loop.mp3",
            durationSeconds: 8,
            sourceName: "SoundBible",
            sourceURL: "https://soundbible.com/1247-Wind.html",
            license: "Public Domain"
        ),
        soundscape(
            id: "snow-cabin",
            title: "Snow Cabin",
            subtitle: "Still winter room tone and soft wind.",
            category: .ambient,
            localFileName: "snow_cabin_loop.mp3",
            durationSeconds: 30,
            sourceName: "SoundBible",
            sourceURL: "https://soundbible.com/1810-Wind.html",
            license: "Attribution 3.0",
            attributionRequired: true,
            attributionText: "Wind by Mark DiAngelo, SoundBible.com"
        ),
        soundscape(
            id: "tropical-jungle",
            title: "Tropical Jungle",
            subtitle: "Dense jungle bed for deep green calm.",
            category: .forest,
            localFileName: "tropical_jungle_loop.mp3",
            durationSeconds: 61,
            sourceName: "SoundBible",
            sourceURL: "https://soundbible.com/1818-Rainforest-Ambience.html",
            license: "Public Domain"
        ),
        soundscape(
            id: "zen-garden",
            title: "Zen Garden",
            subtitle: "Minimal chimes for a softer reset.",
            category: .ambient,
            localFileName: "zen_garden_loop.mp3",
            durationSeconds: 11,
            sourceName: "SoundBible",
            sourceURL: "https://soundbible.com/2030-Daydreaming.html",
            license: "Public Domain"
        )
    ]

    static let downloadablePlaceholders: [Soundscape] = []

    static let all: [Soundscape] = bundledCore + downloadablePlaceholders

    static var defaultSoundscape: Soundscape {
        bundledCore[0]
    }

    static func soundscape(id: String) -> Soundscape? {
        all.first { $0.id == id }
    }

    private static func soundscape(
        id: String,
        title: String,
        subtitle: String,
        category: SoundscapeCategory,
        localFileName: String,
        durationSeconds: Int,
        sourceName: String,
        sourceURL: String,
        license: String,
        attributionRequired: Bool = false,
        attributionText: String? = nil
    ) -> Soundscape {
        Soundscape(
            id: id,
            title: title,
            subtitle: subtitle,
            category: category,
            localFileName: localFileName,
            remoteURL: nil,
            durationSeconds: durationSeconds,
            isLoopable: true,
            isDownloaded: true,
            isPremium: false,
            license: license,
            sourceName: sourceName,
            sourceURL: sourceURL,
            attributionRequired: attributionRequired,
            attributionText: attributionText,
            commercialUseAllowed: true,
            layers: [
                SoundscapeLayer(
                    id: "\(id)-base",
                    title: "\(title) base",
                    localFileName: localFileName,
                    volume: 1.0,
                    loop: true,
                    delaySeconds: nil,
                    randomizeStartTime: true
                )
            ]
        )
    }
}

enum SoundscapeLicenseCatalog {
    static let licenses: [SoundscapeLicense] = [
        license(
            id: "gentle-rain",
            fileName: "gentle_rain_loop.mp3",
            title: "Gentle Rain",
            sourceURL: "https://soundbible.com/2011-Rain-Background.html",
            authorName: "Mike Koenig",
            license: "Attribution 3.0",
            licenseURL: "https://creativecommons.org/licenses/by/3.0/",
            attributionRequired: true,
            attributionText: "Rain Background by Mike Koenig, SoundBible.com",
            notes: "Downloaded from SoundBible as MP3. Replaces the earlier synthesized Pulsar loop."
        ),
        license(
            id: "ocean-waves",
            fileName: "ocean_waves_loop.mp3",
            title: "Ocean Waves",
            sourceURL: "https://soundbible.com/1936-Crisp-Ocean-Waves.html",
            authorName: "Mike Koenig",
            license: "Attribution 3.0",
            licenseURL: "https://creativecommons.org/licenses/by/3.0/",
            attributionRequired: true,
            attributionText: "Crisp Ocean Waves by Mike Koenig, SoundBible.com",
            notes: "Downloaded from SoundBible as MP3. Replaces the earlier synthesized Pulsar loop."
        ),
        license(
            id: "forest-morning",
            fileName: "forest_morning_loop.mp3",
            title: "Forest Morning",
            sourceURL: "https://soundbible.com/1263-Nature-Ambiance.html",
            authorName: "SoundBible",
            license: "Public Domain",
            licenseURL: "https://soundbible.com/1263-Nature-Ambiance.html",
            attributionRequired: false,
            attributionText: nil,
            notes: "Downloaded from SoundBible as MP3. Replaces the earlier synthesized Pulsar loop."
        ),
        license(
            id: "mountain-stream",
            fileName: "mountain_stream_loop.mp3",
            title: "Mountain Stream",
            sourceURL: "https://soundbible.com/2032-Water.html",
            authorName: "Lisa Redfern",
            license: "Public Domain",
            licenseURL: "https://soundbible.com/2032-Water.html",
            attributionRequired: false,
            attributionText: nil,
            notes: "Downloaded from SoundBible as MP3. Replaces the earlier synthesized Pulsar loop."
        ),
        license(
            id: "night-crickets",
            fileName: "night_crickets_loop.mp3",
            title: "Night Crickets",
            sourceURL: "https://soundbible.com/2083-Crickets-Chirping-At-Night.html",
            authorName: "Lisa Redfern",
            license: "Public Domain",
            licenseURL: "https://soundbible.com/2083-Crickets-Chirping-At-Night.html",
            attributionRequired: false,
            attributionText: nil,
            notes: "Downloaded from SoundBible as MP3. Replaces the earlier synthesized Pulsar loop."
        ),
        license(
            id: "fireplace",
            fileName: "fireplace_loop.mp3",
            title: "Fireplace",
            sourceURL: "https://soundbible.com/1902-Fire-Burning.html",
            authorName: "JaBa",
            license: "Attribution 3.0",
            licenseURL: "https://creativecommons.org/licenses/by/3.0/",
            attributionRequired: true,
            attributionText: "Fire Burning by JaBa, SoundBible.com",
            notes: "Downloaded from SoundBible as MP3."
        ),
        license(
            id: "distant-storm",
            fileName: "distant_storm_loop.mp3",
            title: "Distant Storm",
            sourceURL: "https://soundbible.com/886-Distant-Thunder-And-Light-Rain.html",
            authorName: "SoundBible",
            license: "Attribution 3.0",
            licenseURL: "https://creativecommons.org/licenses/by/3.0/",
            attributionRequired: true,
            attributionText: "Distant Thunder And Light Rain from SoundBible.com",
            notes: "Downloaded from SoundBible as MP3."
        ),
        license(
            id: "wind-through-trees",
            fileName: "wind_through_trees_loop.mp3",
            title: "Wind Through Trees",
            sourceURL: "https://soundbible.com/1247-Wind.html",
            authorName: "SoundBible",
            license: "Public Domain",
            licenseURL: "https://soundbible.com/1247-Wind.html",
            attributionRequired: false,
            attributionText: nil,
            notes: "Downloaded from SoundBible as MP3."
        ),
        license(
            id: "snow-cabin",
            fileName: "snow_cabin_loop.mp3",
            title: "Snow Cabin",
            sourceURL: "https://soundbible.com/1810-Wind.html",
            authorName: "Mark DiAngelo",
            license: "Attribution 3.0",
            licenseURL: "https://creativecommons.org/licenses/by/3.0/",
            attributionRequired: true,
            attributionText: "Wind by Mark DiAngelo, SoundBible.com",
            notes: "Downloaded from SoundBible as MP3."
        ),
        license(
            id: "tropical-jungle",
            fileName: "tropical_jungle_loop.mp3",
            title: "Tropical Jungle",
            sourceURL: "https://soundbible.com/1818-Rainforest-Ambience.html",
            authorName: "GlorySunz",
            license: "Public Domain",
            licenseURL: "https://soundbible.com/1818-Rainforest-Ambience.html",
            attributionRequired: false,
            attributionText: nil,
            notes: "Downloaded from SoundBible as MP3."
        ),
        license(
            id: "zen-garden",
            fileName: "zen_garden_loop.mp3",
            title: "Zen Garden",
            sourceURL: "https://soundbible.com/2030-Daydreaming.html",
            authorName: "Lisa Redfern",
            license: "Public Domain",
            licenseURL: "https://soundbible.com/2030-Daydreaming.html",
            attributionRequired: false,
            attributionText: nil,
            notes: "Downloaded from SoundBible as MP3."
        )
    ]

    static func license(for fileName: String) -> SoundscapeLicense? {
        licenses.first { $0.fileName == fileName }
    }

    static func canUseCommercially(fileName: String) -> Bool {
        guard let license = license(for: fileName) else { return false }
        return license.commercialUseAllowed &&
            !license.license.localizedCaseInsensitiveContains("NC") &&
            !license.license.localizedCaseInsensitiveContains("pending") &&
            !license.downloadedAt.isEmpty
    }

    private static func license(
        id: String,
        fileName: String,
        title: String,
        sourceURL: String,
        authorName: String,
        license: String,
        licenseURL: String,
        attributionRequired: Bool,
        attributionText: String?,
        notes: String
    ) -> SoundscapeLicense {
        SoundscapeLicense(
            id: id,
            fileName: fileName,
            title: title,
            sourceName: "SoundBible",
            sourceURL: sourceURL,
            authorName: authorName,
            license: license,
            licenseURL: licenseURL,
            attributionRequired: attributionRequired,
            attributionText: attributionText,
            commercialUseAllowed: true,
            downloadedAt: "2026-07-02",
            notes: notes
        )
    }
}
