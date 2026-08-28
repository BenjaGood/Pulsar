//
//  PulsarPerformanceSignposts.swift
//  Pulsar
//

import Dispatch
import Darwin.Mach
import Foundation
import OSLog

/// A fixed, privacy-safe tab label for performance metadata.
///
/// Do not replace this with a free-form string. Signpost metadata must never
/// include user content, HealthKit values, routes, or stable identifiers.
nonisolated enum PulsarPerformanceTab: String, CaseIterable, Sendable {
    case home
    case fitness
    case food
    case mindfulness
}

nonisolated enum PulsarPerformanceCacheState: String, Sendable {
    case warm
    case cold
    case notApplicable = "na"
}

nonisolated enum PulsarPerformanceOutcome: String, Sendable {
    case completed
    case cancelled
    case failed
}

/// A capture-local correlation token. The generation is monotonic only for
/// this process lifetime and is not a user, account, workout, or device ID.
nonisolated struct PulsarTabSelectionToken: Hashable, Sendable {
    let generation: UInt64
    let from: PulsarPerformanceTab
    let to: PulsarPerformanceTab
}

nonisolated struct PulsarFitnessTabRefreshToken: Hashable, Sendable {
    let generation: UInt64
    let selectionGeneration: UInt64?
}

/// Pure selection lifecycle state, split from OSLog so token and deduplication
/// behavior can be covered by fast unit tests.
nonisolated struct PulsarTabTransitionStateMachine: Sendable {
    static let duplicateSelectionWindowNanoseconds: UInt64 = 250_000_000

    enum Phase: Hashable, Sendable {
        case selectionApplied
        case rootSelected
        case destinationBody
        case destinationAppear
        case destinationUseful
        case wallpaper
        case transitionDone
    }

    struct SelectionStart: Equatable, Sendable {
        let token: PulsarTabSelectionToken
        let isDuplicate: Bool
    }

    private(set) var latestSelection: PulsarTabSelectionToken?
    private(set) var activeSelection: PulsarTabSelectionToken?
    private var nextGeneration: UInt64 = 1
    private var latestSelectionStartedAt: UInt64?
    private var phasesByGeneration: [UInt64: Set<Phase>] = [:]

    mutating func beginSelection(
        from: PulsarPerformanceTab,
        to: PulsarPerformanceTab,
        uptimeNanoseconds: UInt64
    ) -> SelectionStart {
        if let latestSelection,
           latestSelection.from == from,
           latestSelection.to == to,
           let latestSelectionStartedAt,
           uptimeNanoseconds >= latestSelectionStartedAt,
           uptimeNanoseconds - latestSelectionStartedAt <= Self.duplicateSelectionWindowNanoseconds {
            return SelectionStart(token: latestSelection, isDuplicate: true)
        }

        let token = PulsarTabSelectionToken(
            generation: nextGeneration,
            from: from,
            to: to
        )
        nextGeneration &+= 1
        latestSelection = token
        activeSelection = token
        latestSelectionStartedAt = uptimeNanoseconds
        phasesByGeneration[token.generation] = []
        pruneCompletedSelections(keeping: token.generation)
        return SelectionStart(token: token, isDuplicate: false)
    }

    func currentSelection(for tab: PulsarPerformanceTab) -> PulsarTabSelectionToken? {
        guard activeSelection?.to == tab else { return nil }
        return activeSelection
    }

    mutating func completeSelection(_ token: PulsarTabSelectionToken) {
        guard activeSelection == token else { return }
        activeSelection = nil
    }

    mutating func consume(_ phase: Phase, for token: PulsarTabSelectionToken) -> Bool {
        guard phasesByGeneration[token.generation] != nil else { return false }
        return phasesByGeneration[token.generation, default: []].insert(phase).inserted
    }

    private mutating func pruneCompletedSelections(keeping generation: UInt64) {
        let minimumGeneration = generation > 8 ? generation - 8 : 0
        phasesByGeneration = phasesByGeneration.filter { key, _ in
            key >= minimumGeneration
        }
    }
}

/// Coarse, privacy-safe intervals used to correlate Pulsar work with Instruments.
///
/// Keep names stable so device baselines and `XCTOSSignpostMetric` measurements
/// remain comparable across builds. Do not attach HealthKit samples, routes, or
/// other user data to signpost messages.
nonisolated enum PulsarPerformanceSignposts {
    static let subsystem = "tech.aetherial.pulsar"

    enum Category {
        static let launch = "launch"
        static let watchConnectivity = "wc"
        static let fitness = "fitness"
        static let gym = "gym"
        static let run = "run"
        static let muscle = "muscle"
        static let catalog = "catalog"
        static let tab = "tab"
    }

    enum Name {
        static let rootInit = "root_init"
        static let homeUseful = "home_useful"
        static let healthKitSync = "hk_sync"
        static let decode = "decode"
        static let encode = "encode"
        static let apply = "apply"
        static let weekFetch = "week_fetch"
        static let healthKitWeekly = "hk_weekly"
        static let runsHydrate = "runs_hydrate"
        static let historyInit = "history_init"
        static let publishState = "publish_state"
        static let restTick = "rest_tick"
        static let processLocations = "process_locations"
        static let snapshotPublish = "snapshot_publish"
        static let mapPrepare = "map_prepare"
        static let load = "load"

        static let tabSelect = "select"
        static let tabRootSelected = "root_selected"
        static let tabDestinationBody = "dest_body"
        static let tabDestinationAppear = "dest_appear"
        static let tabDestinationUseful = "dest_useful"
        static let tabRefresh = "tab_refresh"
        static let tabChromeReconcile = "chrome_reconcile"
        static let tabWallpaper = "wallpaper"
        static let tabTransitionDone = "transition_done"
    }

    static let launch = OSSignposter(subsystem: subsystem, category: Category.launch)
    static let watchConnectivity = OSSignposter(subsystem: subsystem, category: Category.watchConnectivity)
    static let fitness = OSSignposter(subsystem: subsystem, category: Category.fitness)
    static let gym = OSSignposter(subsystem: subsystem, category: Category.gym)
    static let run = OSSignposter(subsystem: subsystem, category: Category.run)
    static let muscle = OSSignposter(subsystem: subsystem, category: Category.muscle)
    static let catalog = OSSignposter(subsystem: subsystem, category: Category.catalog)
    static let tab = OSSignposter(subsystem: subsystem, category: Category.tab)

    static func measure<T>(
        _ signposter: OSSignposter,
        name: StaticString,
        operation: () throws -> T
    ) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try operation()
    }

    @MainActor private struct TabIntervals {
        var selection: OSSignpostIntervalState?
        var rootSelection: OSSignpostIntervalState?
        var transition: OSSignpostIntervalState?
        var destinationUseful: OSSignpostIntervalState?
        var wallpaper: OSSignpostIntervalState?

        var isEmpty: Bool {
            selection == nil
                && rootSelection == nil
                && transition == nil
                && destinationUseful == nil
                && wallpaper == nil
        }
    }

    @MainActor private static var rootInitState: OSSignpostIntervalState?
    @MainActor private static var didCompleteRootInit = false
    @MainActor private static var homeUsefulState: OSSignpostIntervalState?
    @MainActor private static var didCompleteHomeUseful = false
    @MainActor private static var tabState = PulsarTabTransitionStateMachine()
    @MainActor private static var tabIntervalsByGeneration: [UInt64: TabIntervals] = [:]
    @MainActor private static var nextRefreshGeneration: UInt64 = 1
    @MainActor private static var refreshIntervals: [UInt64: OSSignpostIntervalState] = [:]

    @MainActor static func beginRootInit() {
        guard !didCompleteRootInit, rootInitState == nil else { return }
        rootInitState = launch.beginInterval("root_init")
    }

    @MainActor static func markRootInitialized() {
        guard let state = rootInitState else { return }
        launch.endInterval("root_init", state)
        rootInitState = nil
        didCompleteRootInit = true
    }

    @MainActor static func beginLaunchToHomeUseful() {
        guard !didCompleteHomeUseful, homeUsefulState == nil else { return }
        homeUsefulState = launch.beginInterval("home_useful")
    }

    @MainActor static func markHomeUseful() {
        guard let state = homeUsefulState else { return }
        launch.endInterval("home_useful", state)
        homeUsefulState = nil
        didCompleteHomeUseful = true
    }

    // MARK: - Tab transitions

    @MainActor static func beginTabSelection(
        from: PulsarPerformanceTab,
        to: PulsarPerformanceTab
    ) -> PulsarTabSelectionToken {
        let start = tabState.beginSelection(
            from: from,
            to: to,
            uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        guard !start.isDuplicate else { return start.token }

        closeSupersededTabIntervals(keeping: start.token.generation)
        var intervals = TabIntervals()
        intervals.selection = tab.beginInterval(
            "select",
            "generation=\(start.token.generation, privacy: .public) from=\(from.rawValue, privacy: .public) to=\(to.rawValue, privacy: .public)"
        )
        intervals.transition = tab.beginInterval(
            "transition_done",
            "generation=\(start.token.generation, privacy: .public) to=\(to.rawValue, privacy: .public)"
        )
        tabIntervalsByGeneration[start.token.generation] = intervals
        return start.token
    }

    @MainActor static func markTabSelectionApplied(_ token: PulsarTabSelectionToken) {
        guard tabState.consume(.selectionApplied, for: token),
              var intervals = tabIntervalsByGeneration[token.generation],
              let state = intervals.selection else { return }
        tab.endInterval(
            "select",
            state,
            "generation=\(token.generation, privacy: .public) to=\(token.to.rawValue, privacy: .public)"
        )
        intervals.selection = nil
        store(intervals, for: token.generation)
    }

    @MainActor static func beginTabRootSelection(_ token: PulsarTabSelectionToken) {
        guard tabState.consume(.rootSelected, for: token) else { return }
        var intervals = tabIntervalsByGeneration[token.generation, default: TabIntervals()]
        intervals.rootSelection = tab.beginInterval(
            "root_selected",
            "generation=\(token.generation, privacy: .public) to=\(token.to.rawValue, privacy: .public)"
        )
        tabIntervalsByGeneration[token.generation] = intervals
    }

    @MainActor static func markTabRootSelectionObserved(_ destination: PulsarPerformanceTab) {
        guard let token = tabState.currentSelection(for: destination),
              var intervals = tabIntervalsByGeneration[token.generation],
              let state = intervals.rootSelection else { return }
        tab.endInterval(
            "root_selected",
            state,
            "generation=\(token.generation, privacy: .public) to=\(token.to.rawValue, privacy: .public)"
        )
        intervals.rootSelection = nil
        store(intervals, for: token.generation)
    }

    @MainActor static func measureTabDestinationBody<T>(
        _ destination: PulsarPerformanceTab,
        operation: () throws -> T
    ) rethrows -> T {
        guard let token = tabState.currentSelection(for: destination),
              tabState.consume(.destinationBody, for: token) else {
            return try operation()
        }
        let state = tab.beginInterval(
            "dest_body",
            "generation=\(token.generation, privacy: .public) tab=\(destination.rawValue, privacy: .public)"
        )
        defer {
            tab.endInterval(
                "dest_body",
                state,
                "generation=\(token.generation, privacy: .public) tab=\(destination.rawValue, privacy: .public)"
            )
        }
        return try operation()
    }

    @MainActor static func currentTabSelection(
        for destination: PulsarPerformanceTab
    ) -> PulsarTabSelectionToken? {
        tabState.currentSelection(for: destination)
    }

    @MainActor @discardableResult
    static func markTabDestinationAppeared(
        _ destination: PulsarPerformanceTab
    ) -> PulsarTabSelectionToken? {
        guard let token = tabState.currentSelection(for: destination),
              tabState.consume(.destinationAppear, for: token) else { return nil }
        tab.emitEvent(
            "dest_appear",
            "generation=\(token.generation, privacy: .public) tab=\(destination.rawValue, privacy: .public)"
        )
        var intervals = tabIntervalsByGeneration[token.generation, default: TabIntervals()]
        intervals.destinationUseful = tab.beginInterval(
            "dest_useful",
            "generation=\(token.generation, privacy: .public) tab=\(destination.rawValue, privacy: .public)"
        )
        tabIntervalsByGeneration[token.generation] = intervals
        return token
    }

    @MainActor static func markTabDestinationUseful(
        _ destination: PulsarPerformanceTab,
        cacheState: PulsarPerformanceCacheState
    ) {
        guard let token = tabState.currentSelection(for: destination) else { return }
        markTabDestinationUseful(token, cacheState: cacheState)
    }

    @MainActor static func markTabDestinationUseful(
        _ token: PulsarTabSelectionToken,
        cacheState: PulsarPerformanceCacheState
    ) {
        guard tabState.latestSelection == token,
              tabState.consume(.destinationUseful, for: token) else { return }
        guard var intervals = tabIntervalsByGeneration[token.generation],
              let state = intervals.destinationUseful else {
            tab.emitEvent(
                "dest_useful",
                "generation=\(token.generation, privacy: .public) tab=\(token.to.rawValue, privacy: .public) cache=\(cacheState.rawValue, privacy: .public)"
            )
            return
        }
        tab.endInterval(
            "dest_useful",
            state,
            "generation=\(token.generation, privacy: .public) tab=\(token.to.rawValue, privacy: .public) cache=\(cacheState.rawValue, privacy: .public)"
        )
        intervals.destinationUseful = nil
        store(intervals, for: token.generation)
    }

    @MainActor static func beginFitnessTabRefresh(
        selectionToken: PulsarTabSelectionToken?,
        stale: Bool
    ) -> PulsarFitnessTabRefreshToken {
        let refreshToken = PulsarFitnessTabRefreshToken(
            generation: nextRefreshGeneration,
            selectionGeneration: selectionToken?.generation
        )
        nextRefreshGeneration &+= 1
        refreshIntervals[refreshToken.generation] = fitness.beginInterval(
            "tab_refresh",
            "generation=\(refreshToken.generation, privacy: .public) selection=\(refreshToken.selectionGeneration ?? 0, privacy: .public) stale=\(stale, privacy: .public)"
        )
        return refreshToken
    }

    @MainActor static func endFitnessTabRefresh(
        _ token: PulsarFitnessTabRefreshToken,
        outcome: PulsarPerformanceOutcome
    ) {
        guard let state = refreshIntervals.removeValue(forKey: token.generation) else { return }
        fitness.endInterval(
            "tab_refresh",
            state,
            "generation=\(token.generation, privacy: .public) selection=\(token.selectionGeneration ?? 0, privacy: .public) outcome=\(outcome.rawValue, privacy: .public)"
        )
    }

    @MainActor static func measureTabChromeReconciliation<T>(
        selectionToken: PulsarTabSelectionToken?,
        forced: Bool,
        duplicate: Bool,
        operation: () throws -> T
    ) rethrows -> T {
        let generation = selectionToken?.generation ?? 0
        let state = tab.beginInterval(
            "chrome_reconcile",
            "generation=\(generation, privacy: .public) forced=\(forced, privacy: .public) duplicate=\(duplicate, privacy: .public)"
        )
        defer {
            tab.endInterval(
                "chrome_reconcile",
                state,
                "generation=\(generation, privacy: .public) forced=\(forced, privacy: .public) duplicate=\(duplicate, privacy: .public)"
            )
        }
        return try operation()
    }

    @MainActor @discardableResult
    static func beginTabWallpaperTransition(
        to destination: PulsarPerformanceTab
    ) -> PulsarTabSelectionToken? {
        guard let token = tabState.currentSelection(for: destination),
              tabState.consume(.wallpaper, for: token) else { return nil }
        var intervals = tabIntervalsByGeneration[token.generation, default: TabIntervals()]
        intervals.wallpaper = tab.beginInterval(
            "wallpaper",
            "generation=\(token.generation, privacy: .public) tab=\(destination.rawValue, privacy: .public)"
        )
        tabIntervalsByGeneration[token.generation] = intervals
        return token
    }

    @MainActor static func markTabWallpaperDisplayed(_ destination: PulsarPerformanceTab) {
        guard let token = tabState.currentSelection(for: destination) else { return }
        markTabWallpaperDisplayed(token)
    }

    @MainActor static func markTabWallpaperDisplayed(_ token: PulsarTabSelectionToken) {
        guard var intervals = tabIntervalsByGeneration[token.generation],
              let state = intervals.wallpaper else { return }
        tab.endInterval(
            "wallpaper",
            state,
            "generation=\(token.generation, privacy: .public) tab=\(token.to.rawValue, privacy: .public)"
        )
        intervals.wallpaper = nil
        store(intervals, for: token.generation)
    }

    @MainActor static func markTabTransitionDone(_ token: PulsarTabSelectionToken) {
        guard tabState.consume(.transitionDone, for: token) else { return }
        tabState.completeSelection(token)
        guard var intervals = tabIntervalsByGeneration[token.generation],
              let state = intervals.transition else { return }
        tab.endInterval(
            "transition_done",
            state,
            "generation=\(token.generation, privacy: .public) to=\(token.to.rawValue, privacy: .public)"
        )
        intervals.transition = nil
        store(intervals, for: token.generation)
    }

    @MainActor private static func closeSupersededTabIntervals(keeping generation: UInt64) {
        let supersededIntervals = tabIntervalsByGeneration.filter { key, _ in
            key != generation
        }
        for (oldGeneration, intervals) in supersededIntervals {
            if let state = intervals.selection {
                tab.endInterval("select", state, "generation=\(oldGeneration, privacy: .public) outcome=superseded")
            }
            if let state = intervals.rootSelection {
                tab.endInterval("root_selected", state, "generation=\(oldGeneration, privacy: .public) outcome=superseded")
            }
            if let state = intervals.transition {
                tab.endInterval("transition_done", state, "generation=\(oldGeneration, privacy: .public) outcome=superseded")
            }
            if let state = intervals.destinationUseful {
                tab.endInterval("dest_useful", state, "generation=\(oldGeneration, privacy: .public) outcome=superseded")
            }
            if let state = intervals.wallpaper {
                tab.endInterval("wallpaper", state, "generation=\(oldGeneration, privacy: .public) outcome=superseded")
            }
            tabIntervalsByGeneration.removeValue(forKey: oldGeneration)
        }
    }

    @MainActor private static func store(_ intervals: TabIntervals, for generation: UInt64) {
        if intervals.isEmpty {
            tabIntervalsByGeneration.removeValue(forKey: generation)
        } else {
            tabIntervalsByGeneration[generation] = intervals
        }
    }
}

/// Opt-in checkpoint logging for physical-device investigations. Enable with
/// `PULSAR_PERF_DEBUG_LOGS=1`; normal builds only retain the low-overhead
/// signposts above.
nonisolated enum PulsarPerformanceDiagnostics {
    struct Token: Sendable {
        let name: String
        let startedAt: ContinuousClock.Instant
    }

    static func begin(_ name: String) -> Token {
        let token = Token(name: name, startedAt: .now)
        log(name: name, duration: nil, sampleCount: nil)
        return token
    }

    static func end(_ token: Token, sampleCount: Int? = nil) {
        log(
            name: token.name,
            duration: token.startedAt.duration(to: .now),
            sampleCount: sampleCount
        )
    }

    static func checkpoint(_ name: String, sampleCount: Int? = nil) {
        log(name: name, duration: nil, sampleCount: sampleCount)
    }

    @MainActor private static var eventCounts: [String: Int] = [:]
    @MainActor private static var eventReporterTask: Task<Void, Never>?
    @MainActor private static var instanceCounts: [String: Int] = [:]
    @MainActor private static var peakInstanceCounts: [String: Int] = [:]
    @MainActor private static var stallMonitorTask: Task<Void, Never>?

    /// Counts named main-actor events and reports their one-second rates only
    /// when physical-device diagnostics are explicitly enabled.
    @MainActor static func event(_ name: String) {
        #if DEBUG
        guard isEnabled else { return }
        eventCounts[name, default: 0] += 1
        startEventReporterIfNeeded()
        #endif
    }

    @MainActor static func instanceMounted(_ name: String) {
        #if DEBUG
        guard isEnabled else { return }
        let current = instanceCounts[name, default: 0] + 1
        instanceCounts[name] = current
        peakInstanceCounts[name] = max(peakInstanceCounts[name, default: 0], current)
        logInstance(name)
        #endif
    }

    @MainActor static func instanceUnmounted(_ name: String) {
        #if DEBUG
        guard isEnabled else { return }
        instanceCounts[name] = max(0, instanceCounts[name, default: 0] - 1)
        logInstance(name)
        #endif
    }

    /// A diagnostic-only heartbeat. A late main-actor resume exposes stalls
    /// without changing production scheduling or presentation behavior.
    @MainActor static func startMainActorStallMonitor() {
        #if DEBUG
        guard isEnabled, stallMonitorTask == nil else { return }
        stallMonitorTask = Task { @MainActor in
            while !Task.isCancelled {
                let beforeSleep = ContinuousClock.now
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let elapsed = beforeSleep.duration(to: .now)
                let latency = elapsed - .milliseconds(250)
                if latency >= .milliseconds(100) {
                    log(
                        name: "mainActor.stall",
                        duration: latency,
                        sampleCount: nil
                    )
                }
            }
        }
        #endif
    }

    @MainActor private static func startEventReporterIfNeeded() {
        #if DEBUG
        guard eventReporterTask == nil else { return }
        eventReporterTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                let snapshot = eventCounts
                eventCounts.removeAll(keepingCapacity: true)
                for (name, count) in snapshot.sorted(by: { $0.key < $1.key }) {
                    log(name: "rate.\(name)", duration: nil, sampleCount: count)
                }
            }
        }
        #endif
    }

    @MainActor private static func logInstance(_ name: String) {
        #if DEBUG
        let current = instanceCounts[name, default: 0]
        let peak = peakInstanceCounts[name, default: 0]
        log(name: "instances.\(name).current\(current).peak\(peak)", duration: nil, sampleCount: current)
        #endif
    }

    private static func log(name: String, duration: Duration?, sampleCount: Int?) {
        #if DEBUG
        guard isEnabled else { return }
        let durationText = duration.map { duration in
            let components = duration.components
            let milliseconds = Double(components.seconds) * 1_000
                + Double(components.attoseconds) / 1_000_000_000_000_000
            return String(format: "%.1f", milliseconds)
        } ?? "na"
        let memoryText = currentResidentMemoryMB().map { String(format: "%.1f", $0) } ?? "na"
        print("[PulsarPerf] \(name) durationMs=\(durationText) mainThread=\(Thread.isMainThread) memoryMB=\(memoryText) samples=\(sampleCount.map(String.init) ?? "na")")
        #endif
    }

    #if DEBUG
    /// Read once so a disabled diagnostic event is a constant-time branch.
    /// Re-reading ProcessInfo from high-frequency SwiftUI body paths can itself
    /// amplify the main-thread churn this instrumentation is meant to measure.
    private static let isEnabled = ProcessInfo.processInfo.environment["PULSAR_PERF_DEBUG_LOGS"] == "1"
    #endif

    private static func currentResidentMemoryMB() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.resident_size) / 1_048_576
    }
}
