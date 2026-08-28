import Combine
import Foundation
import Testing
@testable import Pulsar

struct PulsarWorkoutMiniPlayerMetricPolicyTests {
    @Test func outdoorKindsHaveAnExplicitMetricPolicy() {
        for kind in PulsarOutdoorWorkoutKind.allCases {
            #expect(!PulsarWorkoutMiniPlayerMetricPolicy.priority(for: kind).isEmpty)
        }
    }

    @Test func outdoorRunPrioritizesHeartRateThenDistance() {
        let metrics = PulsarWorkoutMiniPlayerMetricPolicy.runMetrics(
            workoutKind: .running,
            heartRate: 154,
            distanceMeters: 2_500,
            paceText: "5:01 /km",
            calories: 180,
            steps: 3_000,
            cadence: 172,
            source: "iPhone"
        )

        #expect(metrics.map(\.kind) == [.heartRate, .distance])
        #expect(metrics.map(\.value) == ["154 bpm", "2.50 km"])
    }

    @Test func missingHeartRateIsOmittedRatherThanRenderedUnavailable() {
        let metrics = PulsarWorkoutMiniPlayerMetricPolicy.runMetrics(
            workoutKind: .running,
            heartRate: nil,
            distanceMeters: 1_000,
            paceText: "6:00 /km",
            calories: nil,
            steps: nil,
            cadence: nil,
            source: "Apple Watch"
        )

        #expect(metrics.map(\.kind) == [.distance, .pace])
        #expect(!metrics.map(\.value).contains("HR unavailable"))
    }

    @Test func gymPrioritizesExerciseAndSetProgress() {
        let metrics = PulsarWorkoutMiniPlayerMetricPolicy.gymMetrics(
            exerciseName: "Bench Press",
            completedSets: 2,
            totalSets: 8,
            heartRate: 120
        )

        #expect(metrics.map(\.kind) == [.exercise, .set])
        #expect(metrics.map(\.value) == ["Bench Press", "2/8 sets"])
    }
}

@MainActor
struct PulsarWorkoutMiniPlayerPresentationTests {
    @Test func localRunPresentationUsesTypedStatusAndOmitsMissingHeartRate() {
        let sessionID = UUID()
        let activeWorkout = PulsarActiveWorkout(
            sessionID: sessionID,
            kind: .run(.running),
            phase: "running",
            updatedAt: .now
        )
        var snapshot = PulsarRunMetricSnapshot.empty
        snapshot.pulsarWorkoutSessionId = sessionID
        snapshot.phase = .running
        snapshot.workoutKind = .running
        snapshot.elapsedTime = 65
        snapshot.movingTime = 60
        snapshot.distanceMeters = 1_000
        snapshot.currentPaceSecondsPerKilometer = 300

        let presentation = PulsarWorkoutMiniPlayerPresenter.run(
            activeWorkout: activeWorkout,
            snapshot: snapshot,
            syncedSessionID: nil
        )

        #expect(presentation?.status == .live)
        #expect(presentation?.elapsedText == "01:05")
        #expect(presentation?.secondaryMetrics.map(\.kind) == [.distance, .pace])
        #expect(presentation?.accessibilitySummary.contains("HR unavailable") == false)
    }

    @Test func verifiedMinimizedWatchGymKeepsAReopenAffordanceBetweenSyncPackets() {
        let sessionID = UUID()
        let activeWorkout = PulsarActiveWorkout(
            sessionID: sessionID,
            kind: .watchGym,
            phase: "active",
            updatedAt: .now
        )

        let presentation = PulsarWorkoutMiniPlayerPresenter.watchGymFallback(
            activeWorkout: activeWorkout
        )

        #expect(presentation?.sessionID == sessionID)
        #expect(presentation?.kind == .watchGym)
        #expect(presentation?.status == .live)

        let finishedWorkout = PulsarActiveWorkout(
            sessionID: sessionID,
            kind: .watchGym,
            phase: "finished",
            updatedAt: .now
        )
        #expect(PulsarWorkoutMiniPlayerPresenter.watchGymFallback(activeWorkout: finishedWorkout) == nil)
    }

    @Test func watchGymFreeWorkoutUsesDedicatedTitleAndOmitsRoutineMetrics() {
        let sessionID = UUID()
        let activeWorkout = PulsarActiveWorkout(
            sessionID: sessionID,
            kind: .watchGym,
            phase: "active",
            updatedAt: .now
        )
        let state = ActiveGymWorkoutState(
            sessionId: sessionID,
            routineId: sessionID,
            routineName: "Open Gym",
            routineEmoji: "🏋️",
            workoutKind: .freeWorkout,
            startedFrom: .appleWatch,
            startedAt: .now.addingTimeInterval(-30),
            elapsedSeconds: 30,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 0,
            totalSets: 0,
            completedSets: 0,
            currentHeartRate: 62,
            averageHeartRate: 61,
            maxHeartRate: 64,
            activeEnergyKilocalories: 1,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: false,
            updatedAt: .now,
            exercises: []
        )

        let presentation = PulsarWorkoutMiniPlayerPresenter.watchGym(
            activeWorkout: activeWorkout,
            state: state,
            isRoutable: true,
            hasLocalGymSession: false
        )

        #expect(presentation?.title == PulsarGymWorkoutKind.freeWorkout.displayName)
        #expect(presentation?.secondaryMetrics.map(\.kind) == [.heartRate])
        #expect(presentation?.secondaryMetrics.map(\.value) == ["62 bpm"])
    }

    @Test func localGymClockPublisherEmitsOnlyDistinctElapsedTicks() {
        let clock = GymWorkoutSessionClock(elapsedSeconds: 42)
        var values: [Int] = []
        let observation = PulsarLocalGymMiniPlayerClockUpdates
            .publisher(for: clock)
            .sink { values.append($0) }

        clock.updateElapsedSeconds(42)
        clock.updateRestCountdown(15)
        clock.updateElapsedSeconds(43)
        clock.updateElapsedSeconds(43)
        clock.updateElapsedSeconds(44)

        #expect(values == [43, 44])
        withExtendedLifetime(observation) {}
    }

    @Test func localGymContentPublisherEmitsOnlyPresentationRelevantChanges() {
        let initialSession = PulsarGymWorkoutSession(
            activeGymState: PulsarPerformanceFixtures.activeGymState(
                exerciseCount: 2,
                setsPerExercise: 4
            )
        )
        let session = CurrentValueSubject<PulsarGymWorkoutSession, Never>(initialSession)
        let focusTarget = CurrentValueSubject<GymWorkoutSetFocusTarget?, Never>(nil)
        let hasSummary = CurrentValueSubject<Bool, Never>(false)
        let currentHeartRate = CurrentValueSubject<Double?, Never>(nil)
        var values: [PulsarLocalGymMiniPlayerContentProjection] = []
        let observation = PulsarLocalGymMiniPlayerContentUpdates.publisher(
            session: session,
            focusTarget: focusTarget,
            hasSummary: hasSummary,
            currentHeartRate: currentHeartRate
        )
        .sink { values.append($0) }

        session.send(initialSession)
        focusTarget.send(nil)
        hasSummary.send(false)
        currentHeartRate.send(nil)
        #expect(values.isEmpty)

        var renamedSession = initialSession
        renamedSession.routineName = "Upper Strength"
        session.send(renamedSession)

        let targetExercise = initialSession.exercises[1]
        let target = GymWorkoutSetFocusTarget(
            exerciseID: targetExercise.id,
            setID: targetExercise.sets[2].id,
            setNumber: 2,
            supersetGroupID: nil
        )
        focusTarget.send(target)
        hasSummary.send(true)
        currentHeartRate.send(126)
        currentHeartRate.send(126)

        #expect(values.count == 4)
        #expect(values[0].routineName == "Upper Strength")
        #expect(values[1].focusedExerciseName == targetExercise.exerciseName)
        #expect(values[2].hasSummary)
        #expect(values[3].currentHeartRate == 126)
        withExtendedLifetime(observation) {}
    }
}

@MainActor
struct PulsarBottomChromeLayoutStoreTests {
    @Test func equivalentInsetsDoNotPublish() {
        let store = PulsarBottomChromeLayoutStore()
        var publicationCount = 0
        let observation = store.objectWillChange.sink {
            publicationCount += 1
        }

        store.update(safeAreaBottom: 34)
        store.update(safeAreaBottom: 34)

        #expect(publicationCount == 1)
        withExtendedLifetime(observation) {}
    }

    @Test func subpixelInsetJitterDoesNotRepublishAtDisplayScale() {
        let store = PulsarBottomChromeLayoutStore()
        var publicationCount = 0
        let observation = store.objectWillChange.sink {
            publicationCount += 1
        }

        store.update(safeAreaBottom: 34.01, displayScale: 3)
        store.update(safeAreaBottom: 34.10, displayScale: 3)

        #expect(store.layout.safeAreaBottom == 34)
        #expect(publicationCount == 1)
        withExtendedLifetime(observation) {}
    }

    @Test func invalidAndNegativeInsetsCannotPerturbTheDefaultLayout() {
        let store = PulsarBottomChromeLayoutStore()
        var publicationCount = 0
        let observation = store.objectWillChange.sink {
            publicationCount += 1
        }

        store.update(safeAreaBottom: -12, displayScale: 3)
        store.update(safeAreaBottom: .nan, displayScale: 3)
        store.update(safeAreaBottom: .infinity, displayScale: 3)

        #expect(store.layout.safeAreaBottom == 0)
        #expect(publicationCount == 0)
        withExtendedLifetime(observation) {}
    }

    @Test func accessoryHeightIsIncludedInScrollableBottomClearance() {
        let store = PulsarBottomChromeLayoutStore()

        store.update(safeAreaBottom: 34, accessoryHeight: 60, displayScale: 3)

        #expect(store.layout.accessoryHeight == 60)
        #expect(
            store.layout.scrollContentBottomMargin ==
                PulsarBottomChromeLayout.floatingNavigationHeight +
                34 +
                60 +
                PulsarBottomChromeLayout.floatingNavigationExtraScrollSpacing
        )
    }

    @Test func accessoryOnlyTransitionsRefreshBottomClearance() {
        let store = PulsarBottomChromeLayoutStore()
        var publishedAccessoryHeights: [CGFloat] = []
        let observation = store.$layout
            .dropFirst()
            .sink { publishedAccessoryHeights.append($0.accessoryHeight) }

        func reconcile(showsMiniWorkout: Bool, showsOrion: Bool) {
            let inputs = PulsarBottomChromeLayoutInputs(
                safeAreaBottom: 34,
                displayScale: 3,
                showsMiniWorkout: showsMiniWorkout,
                showsOrion: showsOrion
            )
            store.update(
                safeAreaBottom: inputs.safeAreaBottom,
                accessoryHeight: inputs.accessoryHeight,
                displayScale: inputs.displayScale
            )
        }

        reconcile(showsMiniWorkout: false, showsOrion: false)
        reconcile(showsMiniWorkout: true, showsOrion: false)
        reconcile(showsMiniWorkout: false, showsOrion: true)
        reconcile(showsMiniWorkout: false, showsOrion: false)

        #expect(publishedAccessoryHeights == [
            0,
            PulsarNativeBottomAccessorySizing.height(for: .workout),
            PulsarNativeBottomAccessorySizing.height(for: .orion),
            0
        ])
        withExtendedLifetime(observation) {}
    }
}

@MainActor
struct PulsarBottomChromeLayoutControllerTests {
    @Test func nativeAccessoryHeightDependsOnlyOnAccessoryKind() {
        #expect(PulsarNativeBottomAccessorySizing.height(for: .orion) == 44)
        #expect(
            PulsarNativeBottomAccessorySizing.height(for: .workout)
                == PulsarWorkoutMiniPlayerSizing.stableNativeAccessoryHeight
        )
        #expect(
            PulsarNativeBottomAccessorySizing.height(for: .workout)
                >= PulsarWorkoutMiniPlayerSizing.compactContentHeight
        )
    }

    @Test func nativeAccessoryOmitsLayoutAdjustmentInteractions() {
        #expect(!PulsarWorkoutMiniPlayerInteractionPolicy.allowsLayoutAdjustment(
            usesNativeAccessoryChrome: true
        ))
        #expect(PulsarWorkoutMiniPlayerInteractionPolicy.allowsLayoutAdjustment(
            usesNativeAccessoryChrome: false
        ))
    }

    @Test func scrollClearanceMatchesNativeAccessoryIntrinsicHeight() {
        let workoutInputs = PulsarBottomChromeLayoutInputs(
            safeAreaBottom: 34,
            displayScale: 3,
            showsMiniWorkout: true,
            showsOrion: false
        )
        let orionInputs = PulsarBottomChromeLayoutInputs(
            safeAreaBottom: 34,
            displayScale: 3,
            showsMiniWorkout: false,
            showsOrion: true
        )

        #expect(workoutInputs.accessoryHeight == PulsarNativeBottomAccessorySizing.height(for: .workout))
        #expect(orionInputs.accessoryHeight == PulsarNativeBottomAccessorySizing.height(for: .orion))
    }

    @Test func systemInlineForcesCompactWithoutChangingPreference() {
        let controller = makeController()
        controller.commit(.expanded)
        controller.setSystemRequiresInline(true)

        #expect(controller.effectiveLayout == .compact)
        #expect(controller.userPreferredLayout == .expanded)

        controller.setSystemRequiresInline(false)
        #expect(controller.effectiveLayout == .expanded)
    }

    @Test func repeatedSystemInlineRequirementDoesNotPublish() {
        let controller = makeController()
        var publicationCount = 0
        let observation = controller.objectWillChange.sink {
            publicationCount += 1
        }

        controller.setSystemRequiresInline(false)
        #expect(publicationCount == 0)

        controller.setSystemRequiresInline(true)
        #expect(publicationCount == 1)

        controller.setSystemRequiresInline(true)
        #expect(publicationCount == 1)
        withExtendedLifetime(observation) {}
    }

    @Test func downwardDragCommitsCompactLayout() {
        let controller = makeController()
        controller.updateDrag(translation: 40)
        controller.endDrag(translation: 40, predictedTranslation: 44, reduceMotion: false)

        #expect(controller.userPreferredLayout == .compact)
        #expect(controller.visualProgress == 1)
    }

    @Test func upwardDragRestoresExpandedLayout() {
        let controller = makeController(initialLayout: .compact)
        controller.updateDrag(translation: -32)
        controller.endDrag(translation: -32, predictedTranslation: -35, reduceMotion: false)

        #expect(controller.userPreferredLayout == .expanded)
        #expect(controller.visualProgress == 0)
    }

    @Test func effectiveLayoutPublisherEmitsOnlySemanticLayoutChanges() {
        let controller = makeController()
        var layouts: [PulsarBottomChromeBarLayout] = []
        let observation = controller.effectiveLayoutPublisher
            .dropFirst()
            .sink { layouts.append($0) }

        controller.updateDrag(translation: 10)
        controller.updateDrag(translation: 10)
        controller.updateDrag(translation: 40)
        controller.updateDrag(translation: 40)

        #expect(layouts == [.compact])
        withExtendedLifetime(observation) {}
    }

    @Test(arguments: [
        PulsarBottomChromeBarLayout.expanded,
        PulsarBottomChromeBarLayout.compact
    ])
    func inlineTransitionCancelsActiveDragAndRestoresPreference(
        preference: PulsarBottomChromeBarLayout
    ) {
        let controller = makeController(initialLayout: preference)
        let translation: CGFloat = preference == .expanded ? 40 : -40
        controller.updateDrag(translation: translation)
        #expect(controller.isDragging)

        controller.setSystemRequiresInline(true)
        controller.endDrag(
            translation: translation,
            predictedTranslation: translation,
            reduceMotion: false
        )
        controller.setSystemRequiresInline(false)

        #expect(!controller.isDragging)
        #expect(controller.dragProgress == (preference == .compact ? 1 : 0))
        #expect(controller.effectiveLayout == preference)
    }

    private func makeController(initialLayout: PulsarBottomChromeBarLayout = .expanded) -> PulsarBottomChromeLayoutController {
        let suiteName = "PulsarBottomChromeLayoutControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(initialLayout.rawValue, forKey: PulsarBottomChromeLayoutController.preferenceKey)
        return PulsarBottomChromeLayoutController(defaults: defaults, playsHaptics: false)
    }
}
