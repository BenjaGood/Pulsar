import Combine
import Foundation
import SwiftUI

@MainActor
final class PulsarSyncBannerCenter: ObservableObject {
    static let shared = PulsarSyncBannerCenter()

    enum State: Equatable {
        case hidden
        case syncing(String)
        case success(String)
        case failure(String)
    }

    @Published private(set) var state: State = .hidden

    private var dismissTask: Task<Void, Never>?

    func showSyncing(message: String = "Syncing health data…") {
        dismissTask?.cancel()
        dismissTask = nil
        if setStateIfChanged(.syncing(message)) {
            PulsarSyncDebugLogger.log("sync started")
        }
    }

    func showFailure(message: String = "Unable to sync. Showing latest data.") {
        dismissTask?.cancel()
        dismissTask = nil
        if setStateIfChanged(.failure(message)) {
            PulsarSyncDebugLogger.log("sync failed: \(message)")
        }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_100_000_000)
            if !Task.isCancelled {
                PulsarSyncDebugLogger.log("visible sync pill hidden")
                hideWithAnimation()
            }
        }
    }

    func showSuccess(message: String = "Health data synced") {
        dismissTask?.cancel()
        dismissTask = nil
        if setStateIfChanged(.success(message)) {
            PulsarSyncDebugLogger.log("sync finished successfully")
        }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_450_000_000)
            if !Task.isCancelled {
                PulsarSyncDebugLogger.log("visible sync pill hidden")
                hideWithAnimation()
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard state != .hidden else { return }
        if state != .hidden {
            PulsarSyncDebugLogger.log("sync finished")
            PulsarSyncDebugLogger.log("visible sync pill hidden")
        }
        hideWithAnimation()
    }

    @discardableResult
    private func setStateIfChanged(_ newState: State) -> Bool {
        guard state != newState else { return false }
        withAnimation(.smooth(duration: 0.25)) {
            state = newState
        }
        return true
    }

    private func hideWithAnimation() {
        withAnimation(.smooth(duration: 0.25)) {
            state = .hidden
        }
    }
}
