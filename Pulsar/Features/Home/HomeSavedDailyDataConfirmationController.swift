import Combine
import Foundation
import SwiftUI

@MainActor
final class HomeSavedDailyDataConfirmationController: ObservableObject {
    nonisolated static let duration: Duration = .seconds(5)
    nonisolated static let animation = Animation.smooth(duration: 0.28)

    @Published private(set) var isPresented = false

    private let duration: Duration
    private var dismissTask: Task<Void, Never>?

    init(duration: Duration = .seconds(5)) {
        self.duration = duration
    }

    deinit {
        dismissTask?.cancel()
    }

    func present() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(Self.animation) {
            isPresented = true
        }
        dismissTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.duration)
            guard !Task.isCancelled else { return }
            withAnimation(Self.animation) {
                self.isPresented = false
            }
            self.dismissTask = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard isPresented else { return }
        withAnimation(Self.animation) {
            isPresented = false
        }
    }
}
