//
//  HomeSavedDailyDataConfirmationTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct HomeSavedDailyDataConfirmationTests {
    @Test func cachedSavedDailyDataStatusIsNotAPersistentBanner() {
        #expect(
            !HomeViewModel.showsPersistentHealthKitStatusBanner(
                healthKitStatus: HomeViewModel.savedDailyDataBannerMessage
            )
        )
    }

    @Test func connectedStatusDoesNotShowAPersistentBanner() {
        #expect(!HomeViewModel.showsPersistentHealthKitStatusBanner(healthKitStatus: "HealthKit connected"))
        #expect(
            !HomeViewModel.showsPersistentHealthKitStatusBanner(
                healthKitStatus: "HealthKit connected · Oura synced"
            )
        )
    }

    @Test func otherHealthKitStatusesRemainPersistent() {
        #expect(HomeViewModel.showsPersistentHealthKitStatusBanner(healthKitStatus: "HealthKit unavailable"))
        #expect(HomeViewModel.showsPersistentHealthKitStatusBanner(healthKitStatus: "Health permission required"))
        #expect(HomeViewModel.showsPersistentHealthKitStatusBanner(healthKitStatus: "No saved data for selected day"))
        #expect(HomeViewModel.showsPersistentHealthKitStatusBanner(healthKitStatus: "Showing latest available data"))
    }

    @Test func presentShowsTheConfirmationUntilTheDurationElapses() async throws {
        let controller = HomeSavedDailyDataConfirmationController(duration: .milliseconds(60))
        controller.present()
        #expect(controller.isPresented)

        try await Task.sleep(for: .milliseconds(30))
        #expect(controller.isPresented)

        try await Task.sleep(for: .milliseconds(60))
        #expect(!controller.isPresented)
    }

    @Test func presentingAgainCancelsThePreviousDismissalTask() async throws {
        let controller = HomeSavedDailyDataConfirmationController(duration: .milliseconds(80))
        controller.present()
        try await Task.sleep(for: .milliseconds(30))
        controller.present()

        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.isPresented)

        try await Task.sleep(for: .milliseconds(60))
        #expect(!controller.isPresented)
    }

    @Test func dismissCancelsAPendingAutoHide() async throws {
        let controller = HomeSavedDailyDataConfirmationController(duration: .milliseconds(80))
        controller.present()
        controller.dismiss()
        #expect(!controller.isPresented)

        try await Task.sleep(for: .milliseconds(120))
        #expect(!controller.isPresented)
    }

    @Test func confirmationMessageStaysExactlySavedDailyData() {
        #expect(HomeViewModel.savedDailyDataBannerMessage == "Showing saved daily data")
    }
}
