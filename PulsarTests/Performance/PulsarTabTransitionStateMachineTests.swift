//
//  PulsarTabTransitionStateMachineTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

final class PulsarTabTransitionStateMachineTests: XCTestCase {
    func testDuplicateSelectionWithinWindowReusesGeneration() {
        var state = PulsarTabTransitionStateMachine()
        let first = state.beginSelection(
            from: .home,
            to: .fitness,
            uptimeNanoseconds: 1_000_000_000
        )
        let duplicate = state.beginSelection(
            from: .home,
            to: .fitness,
            uptimeNanoseconds: 1_200_000_000
        )

        XCTAssertFalse(first.isDuplicate)
        XCTAssertTrue(duplicate.isDuplicate)
        XCTAssertEqual(duplicate.token, first.token)
    }

    func testSameSelectionOutsideWindowGetsNewGeneration() {
        var state = PulsarTabTransitionStateMachine()
        let first = state.beginSelection(
            from: .home,
            to: .fitness,
            uptimeNanoseconds: 1_000_000_000
        )
        let next = state.beginSelection(
            from: .home,
            to: .fitness,
            uptimeNanoseconds: 1_300_000_001
        )

        XCTAssertFalse(next.isDuplicate)
        XCTAssertGreaterThan(next.token.generation, first.token.generation)
    }

    func testDifferentDestinationAlwaysGetsNewGeneration() {
        var state = PulsarTabTransitionStateMachine()
        let fitness = state.beginSelection(
            from: .home,
            to: .fitness,
            uptimeNanoseconds: 1_000_000_000
        )
        let food = state.beginSelection(
            from: .fitness,
            to: .food,
            uptimeNanoseconds: 1_001_000_000
        )

        XCTAssertFalse(food.isDuplicate)
        XCTAssertEqual(food.token.generation, fitness.token.generation + 1)
        XCTAssertEqual(state.currentSelection(for: .food), food.token)
        XCTAssertNil(state.currentSelection(for: .fitness))
    }

    func testEachPhaseIsConsumedOncePerSelection() {
        var state = PulsarTabTransitionStateMachine()
        let token = state.beginSelection(
            from: .home,
            to: .fitness,
            uptimeNanoseconds: 1_000_000_000
        ).token

        for phase in [
            PulsarTabTransitionStateMachine.Phase.selectionApplied,
            .rootSelected,
            .destinationBody,
            .destinationAppear,
            .destinationUseful,
            .wallpaper,
            .transitionDone
        ] {
            XCTAssertTrue(state.consume(phase, for: token), "Expected first \(phase) to be recorded")
            XCTAssertFalse(state.consume(phase, for: token), "Expected duplicate \(phase) to be ignored")
        }
    }

    func testPhasesRemainIndependentAcrossGenerations() {
        var state = PulsarTabTransitionStateMachine()
        let first = state.beginSelection(
            from: .home,
            to: .fitness,
            uptimeNanoseconds: 1_000_000_000
        ).token
        XCTAssertTrue(state.consume(.destinationAppear, for: first))

        let second = state.beginSelection(
            from: .fitness,
            to: .home,
            uptimeNanoseconds: 1_010_000_000
        ).token

        XCTAssertTrue(state.consume(.destinationAppear, for: second))
        XCTAssertFalse(state.consume(.destinationAppear, for: first))
    }

    func testCompletionExpiresImplicitCorrelationButKeepsExactTokenUsable() {
        var state = PulsarTabTransitionStateMachine()
        let token = state.beginSelection(
            from: .home,
            to: .fitness,
            uptimeNanoseconds: 1_000_000_000
        ).token

        state.completeSelection(token)

        XCTAssertNil(state.currentSelection(for: .fitness))
        XCTAssertEqual(state.latestSelection, token)
        XCTAssertTrue(state.consume(.destinationUseful, for: token))
    }
}
