//
//  PulsarWorkoutStartupTrace.swift
//  Pulsar
//

import Foundation
import os

enum PulsarWorkoutStartupTrace: Sendable {
    // Default isolation is MainActor; diagnostics are emitted from WatchConnectivity
    // codec / detached persist paths as well as UI.
    nonisolated(unsafe) private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated private static let logger = Logger(subsystem: "aetherial.Pulsar", category: "startup")
    nonisolated private static let seqLock = NSLock()
    nonisolated(unsafe) private static var seq: UInt64 = 0
    nonisolated private static let onceLock = NSLock()
    nonisolated(unsafe) private static var onceKeys = Set<String>()
    nonisolated private static let formatLock = NSLock()
    nonisolated private static let rateTracker = RateTracker()

    /// Console.app filter for freeze reproductions. Always emitted via
    /// `os.Logger` so physical-device logs are visible without Xcode.
    /// Identical `seq=` values on two Console rows mean Logger+print dual-sink,
    /// not two handlers.
    nonisolated static func diag(_ message: String) {
        emit(prefix: "[PulsarDiag]", message: message)
    }

    nonisolated static func diagOnce(_ key: String, _ message: String) {
        onceLock.lock()
        let inserted = onceKeys.insert(key).inserted
        onceLock.unlock()
        guard inserted else { return }
        diag(message)
    }

    nonisolated static func threadTag() -> String {
        "main=\(Thread.isMainThread)"
    }

    nonisolated static func elapsedMs(since start: Date) -> Int {
        Int((Date().timeIntervalSince(start) * 1000).rounded())
    }

    nonisolated static func phone(_ message: String) {
        emit(prefix: "[iPhone][Workout]", message: message)
    }

    nonisolated static func watch(_ message: String) {
        emit(prefix: "[Watch][Workout]", message: message)
    }

    nonisolated static func lifecycle(_ message: String) {
        emit(prefix: "[PulsarLifecycle]", message: message)
    }

    nonisolated static func identity(workoutID: UUID?, requestID: UUID?) -> String {
        "workoutID=\(workoutID?.uuidString ?? "none") requestID=\(requestID?.uuidString ?? "none")"
    }

    /// Aggregates to one Console line per second. Safe to call from body
    /// evaluation and from any thread.
    nonisolated static func count(_ bucket: String, bytes: Int = 0) {
        rateTracker.add(bucket, bytes: bytes)
    }

    nonisolated static func recordDefaultsWrite(key: String, bytes: Int, elapsedMs: Int) {
        count("[DefaultsWrite] \(key)", bytes: bytes)
        guard elapsedMs >= 10 else { return }
        diag(
            "[DefaultsWrite] key=\(key) bytes=\(bytes) elapsedMs=\(elapsedMs) \(threadTag())"
        )
    }

    nonisolated static func recordEncode(kind: String, bytes: Int, elapsedMs: Int) {
        count("[WCEncode] \(kind)", bytes: bytes)
        diag(
            "[WCEncode] kind=\(kind) bytes=\(bytes) elapsedMs=\(elapsedMs) \(threadTag())"
        )
    }

    nonisolated static func remoteConflict(
        expectedWorkoutID: UUID?,
        expectedRequestID: UUID?,
        watchWorkoutID: UUID?,
        watchRequestID: UUID? = nil,
        watchHKState: String,
        action: String
    ) {
        phone(
            "[RemoteConflict] expectedWorkoutID=\(expectedWorkoutID?.uuidString ?? "none") expectedRequestID=\(expectedRequestID?.uuidString ?? "none") watchWorkoutID=\(watchWorkoutID?.uuidString ?? "none") watchRequestID=\(watchRequestID?.uuidString ?? "none") watchHKState=\(watchHKState) action=\(action)"
        )
    }

    nonisolated private static func nextSeq() -> UInt64 {
        seqLock.lock()
        seq += 1
        let value = seq
        seqLock.unlock()
        return value
    }

    nonisolated private static func emit(prefix: String, message: String) {
        let seq = nextSeq()
        formatLock.lock()
        let timestamp = timestampFormatter.string(from: Date())
        formatLock.unlock()
        let line = "\(prefix) seq=\(seq) \(timestamp) \(message)"
        logger.notice("\(line, privacy: .public)")
        PulsarSyncDebugLogger.log(line)
    }

    private final class RateTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        private var bytes: [String: Int] = [:]
        private var reporterStarted = false

        nonisolated func add(_ bucket: String, bytes: Int) {
            lock.lock()
            counts[bucket, default: 0] += 1
            if bytes > 0 {
                self.bytes[bucket, default: 0] += bytes
            }
            let shouldStart = !reporterStarted
            if shouldStart {
                reporterStarted = true
            }
            lock.unlock()
            if shouldStart {
                startReporter()
            }
        }

        nonisolated private func startReporter() {
            Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    let snapshot = self.snapshotAndReset()
                    for (bucket, count) in snapshot.counts.sorted(by: { $0.key < $1.key }) {
                        let bytes = snapshot.bytes[bucket] ?? 0
                        let bytesSuffix = bytes > 0 ? " bytes=\(bytes)" : ""
                        PulsarWorkoutStartupTrace.diag(
                            "\(bucket) count=\(count)/sec\(bytesSuffix) \(PulsarWorkoutStartupTrace.threadTag())"
                        )
                    }
                }
            }
        }

        nonisolated private func snapshotAndReset() -> (counts: [String: Int], bytes: [String: Int]) {
            lock.lock()
            let counts = self.counts
            let bytes = self.bytes
            self.counts.removeAll(keepingCapacity: true)
            self.bytes.removeAll(keepingCapacity: true)
            lock.unlock()
            return (counts, bytes)
        }
    }
}
