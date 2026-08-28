import Combine
import SwiftUI
import UIKit

enum PulsarBottomChromeBarLayout: String, Equatable {
    case expanded
    case compact
}

@MainActor
final class PulsarBottomChromeLayoutController: ObservableObject {
    static let preferenceKey = "pulsar.workoutMiniBar.preferredLayout"

    @Published private(set) var userPreferredLayout: PulsarBottomChromeBarLayout
    @Published private(set) var systemRequiresInline = false
    @Published private(set) var dragProgress: CGFloat = 0
    @Published private(set) var isDragging = false

    private let defaults: UserDefaults
    private let playsHaptics: Bool

    init(defaults: UserDefaults = .standard, playsHaptics: Bool = true) {
        self.defaults = defaults
        self.playsHaptics = playsHaptics
        userPreferredLayout = defaults.string(forKey: Self.preferenceKey)
            .flatMap(PulsarBottomChromeBarLayout.init(rawValue:)) ?? .expanded
        dragProgress = userPreferredLayout == .compact ? 1 : 0
    }

    var effectiveLayout: PulsarBottomChromeBarLayout {
        Self.effectiveLayout(
            userPreferredLayout: userPreferredLayout,
            systemRequiresInline: systemRequiresInline,
            dragProgress: dragProgress,
            isDragging: isDragging
        )
    }

    var effectiveLayoutPublisher: AnyPublisher<PulsarBottomChromeBarLayout, Never> {
        Publishers.CombineLatest4(
            $userPreferredLayout,
            $systemRequiresInline,
            $dragProgress,
            $isDragging
        )
        .map { values in
            Self.effectiveLayout(
                userPreferredLayout: values.0,
                systemRequiresInline: values.1,
                dragProgress: values.2,
                isDragging: values.3
            )
        }
        .removeDuplicates()
        .eraseToAnyPublisher()
    }

    var visualProgress: CGFloat {
        systemRequiresInline ? 1 : (isDragging ? dragProgress : (userPreferredLayout == .compact ? 1 : 0))
    }

    func setSystemRequiresInline(_ requiresInline: Bool) {
        guard systemRequiresInline != requiresInline else { return }
        systemRequiresInline = requiresInline
        guard requiresInline else { return }
        if isDragging {
            isDragging = false
        }
        let preferredProgress: CGFloat = userPreferredLayout == .compact ? 1 : 0
        if dragProgress != preferredProgress {
            dragProgress = preferredProgress
        }
    }

    func updateDrag(translation: CGFloat) {
        guard !systemRequiresInline else { return }
        if !isDragging {
            isDragging = true
        }
        let origin: CGFloat = userPreferredLayout == .compact ? 1 : 0
        let nextProgress = min(max(origin + translation / 60, 0), 1)
        if abs(nextProgress - dragProgress) > 0.001 {
            dragProgress = nextProgress
        }
    }

    func endDrag(translation: CGFloat, predictedTranslation: CGFloat, reduceMotion: Bool) {
        guard !systemRequiresInline else { return }
        let projectedDelta = predictedTranslation - translation
        let target: PulsarBottomChromeBarLayout
        if projectedDelta > 45 || translation > 36 {
            target = .compact
        } else if projectedDelta < -45 || translation < -28 {
            target = .expanded
        } else {
            target = dragProgress >= 0.5 ? .compact : .expanded
        }
        guard target != userPreferredLayout else {
            isDragging = false
            dragProgress = userPreferredLayout == .compact ? 1 : 0
            return
        }
        commit(target, reduceMotion: reduceMotion)
    }

    func commit(_ layout: PulsarBottomChromeBarLayout, reduceMotion: Bool = false) {
        if userPreferredLayout != layout {
            userPreferredLayout = layout
            defaults.set(layout.rawValue, forKey: Self.preferenceKey)
        }
        if isDragging {
            isDragging = false
        }
        let resolvedProgress: CGFloat = layout == .compact ? 1 : 0
        if dragProgress != resolvedProgress {
            dragProgress = resolvedProgress
        }
        if playsHaptics {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    private static func effectiveLayout(
        userPreferredLayout: PulsarBottomChromeBarLayout,
        systemRequiresInline: Bool,
        dragProgress: CGFloat,
        isDragging: Bool
    ) -> PulsarBottomChromeBarLayout {
        if systemRequiresInline { return .compact }
        if isDragging { return dragProgress >= 0.5 ? .compact : .expanded }
        return userPreferredLayout
    }
}
