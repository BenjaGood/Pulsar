//
//  PulsarGPSWorkoutModels.swift
//  Pulsar
//

import CoreLocation
import Foundation

enum GPSWorkoutRouteSource: String, Codable, Hashable {
    case pulsarLive
    case healthKitRoute
    case imported
    case unknown

    nonisolated var displayName: String {
        switch self {
        case .pulsarLive:
            "Pulsar GPS"
        case .healthKitRoute:
            "HealthKit Route"
        case .imported:
            "Imported Route"
        case .unknown:
            "GPS Route"
        }
    }
}

struct GPSRoutePoint: Codable, Hashable, Identifiable {
    nonisolated var id: String { "\(timestamp.timeIntervalSince1970)-\(latitude)-\(longitude)" }

    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var horizontalAccuracy: Double?
    var verticalAccuracy: Double?
    var timestamp: Date

    nonisolated init(
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        verticalAccuracy: Double? = nil,
        timestamp: Date = Date()
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.timestamp = timestamp
    }

    nonisolated init(location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            verticalAccuracy: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil,
            timestamp: location.timestamp
        )
    }

    nonisolated init(runCoordinate: PulsarRunCoordinate) {
        self.init(
            latitude: runCoordinate.latitude,
            longitude: runCoordinate.longitude,
            altitude: runCoordinate.altitude,
            horizontalAccuracy: runCoordinate.horizontalAccuracy,
            verticalAccuracy: runCoordinate.verticalAccuracy,
            timestamp: runCoordinate.timestamp
        )
    }

    nonisolated var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    nonisolated var runCoordinate: PulsarRunCoordinate {
        PulsarRunCoordinate(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            timestamp: timestamp
        )
    }
}

struct ElevationSample: Codable, Hashable, Identifiable {
    nonisolated var id: Int { index }

    var index: Int
    var distanceMeters: Double
    var elapsedTime: TimeInterval
    var elevationMeters: Double
    var timestamp: Date
}

struct GPSRouteBounds: Codable, Hashable {
    var minimumLatitude: Double
    var maximumLatitude: Double
    var minimumLongitude: Double
    var maximumLongitude: Double

    nonisolated var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (minimumLatitude + maximumLatitude) / 2,
            longitude: (minimumLongitude + maximumLongitude) / 2
        )
    }

    nonisolated var latitudeDelta: Double {
        max(0.006, (maximumLatitude - minimumLatitude) * 1.35)
    }

    nonisolated var longitudeDelta: Double {
        max(0.006, (maximumLongitude - minimumLongitude) * 1.35)
    }
}

struct GPSRouteElevationMetrics: Codable, Hashable {
    var gainMeters: Double
    var lossMeters: Double
    var minimumElevationMeters: Double?
    var maximumElevationMeters: Double?
}

struct GPSWorkoutRoute: Codable, Hashable {
    var points: [GPSRoutePoint]
    var source: GPSWorkoutRouteSource
    var capturedAt: Date?

    nonisolated init(
        points: [GPSRoutePoint],
        source: GPSWorkoutRouteSource = .unknown,
        capturedAt: Date? = nil
    ) {
        self.points = points.sorted { $0.timestamp < $1.timestamp }
        self.source = source
        self.capturedAt = capturedAt
    }

    nonisolated init(
        runCoordinates: [PulsarRunCoordinate],
        source: GPSWorkoutRouteSource = .unknown,
        capturedAt: Date? = nil
    ) {
        self.init(
            points: runCoordinates.map(GPSRoutePoint.init(runCoordinate:)),
            source: source,
            capturedAt: capturedAt
        )
    }

    nonisolated var runCoordinates: [PulsarRunCoordinate] {
        points.map(\.runCoordinate)
    }

    nonisolated var routePointCount: Int {
        points.count
    }

    nonisolated var bounds: GPSRouteBounds? {
        guard let first = points.first else { return nil }
        return points.dropFirst().reduce(
            GPSRouteBounds(
                minimumLatitude: first.latitude,
                maximumLatitude: first.latitude,
                minimumLongitude: first.longitude,
                maximumLongitude: first.longitude
            )
        ) { partial, point in
            GPSRouteBounds(
                minimumLatitude: min(partial.minimumLatitude, point.latitude),
                maximumLatitude: max(partial.maximumLatitude, point.latitude),
                minimumLongitude: min(partial.minimumLongitude, point.longitude),
                maximumLongitude: max(partial.maximumLongitude, point.longitude)
            )
        }
    }

    nonisolated var elevationMetrics: GPSRouteElevationMetrics {
        var previousAltitude: Double?
        var gain = 0.0
        var loss = 0.0
        let elevations = points.compactMap(\.altitude)

        for point in points {
            guard let altitude = point.altitude else { continue }
            guard point.verticalAccuracy.map({ $0 <= 18 }) ?? true else { continue }
            if let previousAltitude {
                let delta = altitude - previousAltitude
                if delta >= 1.5 {
                    gain += delta
                } else if delta <= -1.5 {
                    loss += abs(delta)
                }
            }
            previousAltitude = altitude
        }

        return GPSRouteElevationMetrics(
            gainMeters: gain,
            lossMeters: loss,
            minimumElevationMeters: elevations.min(),
            maximumElevationMeters: elevations.max()
        )
    }

    nonisolated var elevationSamples: [ElevationSample] {
        guard let firstPoint = points.first else { return [] }
        var previousLocation: CLLocation?
        var cumulativeDistance = 0.0

        return points.enumerated().compactMap { index, point in
            let location = CLLocation(
                coordinate: point.coordinate,
                altitude: point.altitude ?? 0,
                horizontalAccuracy: point.horizontalAccuracy ?? -1,
                verticalAccuracy: point.verticalAccuracy ?? -1,
                timestamp: point.timestamp
            )
            if let previousLocation {
                cumulativeDistance += max(0, location.distance(from: previousLocation))
            }
            previousLocation = location

            guard let altitude = point.altitude else { return nil }
            return ElevationSample(
                index: index,
                distanceMeters: cumulativeDistance,
                elapsedTime: max(0, point.timestamp.timeIntervalSince(firstPoint.timestamp)),
                elevationMeters: altitude,
                timestamp: point.timestamp
            )
        }
    }
}

struct WorkoutSummaryMetrics: Codable, Hashable {
    var workoutType: PulsarOutdoorWorkoutKind
    var startedAt: Date
    var duration: TimeInterval
    var movingTime: TimeInterval
    var stoppedTime: TimeInterval
    var distanceMeters: Double
    var averagePaceSecondsPerKilometer: Double?
    var averageSpeedMetersPerSecond: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergyKilocalories: Double?
    var elevationGainMeters: Double
    var elevationLossMeters: Double
    var minimumElevationMeters: Double?
    var maximumElevationMeters: Double?
    var sourceDevice: String
    var routePointCount: Int

    nonisolated init(summary: PulsarRunSummary) {
        let route = summary.gpsRoute
        self.workoutType = summary.workoutKind
        self.startedAt = summary.startedAt
        self.duration = summary.elapsedTime
        self.movingTime = summary.movingTime
        self.stoppedTime = summary.stoppedTime
        self.distanceMeters = summary.distanceMeters
        self.averagePaceSecondsPerKilometer = summary.averagePaceSecondsPerKilometer
        self.averageSpeedMetersPerSecond = summary.averageSpeedMetersPerSecond
        self.averageHeartRate = summary.averageHeartRate
        self.maxHeartRate = summary.maxHeartRate
        self.activeEnergyKilocalories = summary.activeEnergyKilocalories
        self.elevationGainMeters = summary.effectiveElevationGainMeters
        self.elevationLossMeters = summary.effectiveElevationLossMeters
        self.minimumElevationMeters = summary.minimumElevationMeters ?? route.elevationMetrics.minimumElevationMeters
        self.maximumElevationMeters = summary.maximumElevationMeters ?? route.elevationMetrics.maximumElevationMeters
        self.sourceDevice = summary.sourceDeviceName
        self.routePointCount = route.routePointCount
    }
}
