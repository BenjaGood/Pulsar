# Workout Start Lifecycle — Phase 5 Validation Matrix

Device signoff checklist for the Phase 1–4 workout-start lifecycle fixes. Simulator coverage is necessary but **not sufficient** for P0; HealthKit, `startWatchApp`, WatchConnectivity, and mirroring require a real iPhone + Apple Watch.

## Acceptance criteria

- [ ] Start never shows Done unless that session reached active, then completed
- [ ] Active UI only after verified init (local HK running or Watch ack)
- [ ] Paired, installed Watch can receive a HealthKit launch attempt even when WC is not interactively reachable
- [ ] Watch available ⇒ session starts and HR can flow; else clear error / fallback
- [ ] Double Start ⇒ one attempt
- [ ] Stale finished / delayed WC cannot complete a new session
- [ ] All workout types share the same lifecycle guarantees
- [ ] Unit suites for ownership Phases 3–5 + start coordinator + completion store pass

## Automated coverage (simulator)

Run on an explicit iPhone simulator id (name-only destinations are unreliable):

```bash
xcodebuild -project Pulsar.xcodeproj -scheme Pulsar \
  -destination 'platform=iOS Simulator,id=<IPHONE_SIM_UDID>' \
  -only-testing:PulsarTests/WorkoutOwnershipPhase3Tests \
  -only-testing:PulsarTests/WorkoutOwnershipPhase4Tests \
  -only-testing:PulsarTests/WorkoutOwnershipPhase5Tests \
  -only-testing:PulsarTests/PulsarWorkoutStartCoordinatorTests \
  -only-testing:PulsarTests/WorkoutCompletionPresentationStoreTests \
  -only-testing:PulsarTests/GymCrossDeviceStartTests \
  test
```

## Priority device scenarios

Do these first. Capture Console filters: `WorkoutLifecycle`, `PulsarSummary`, `PulsarState`, `PulsarSync`.

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| P1 | After finished gym → Start Watch gym | Finish a Watch gym, dismiss Done, immediately Start another | Connecting/pending → live; never Done from stale finished |
| P2 | Watch WC not reachable | Keep Watch paired/installed with app cold or wrist down | HealthKit launch is attempted; durable identity queues; no immediate iPhone-only fallback |
| P3 | Start then background | Start Watch gym, lock iPhone for 20–30s | Still connecting or live when returning; no premature Done |
| P4 | Rapid double-tap Start | Double-tap Start | Single attempt; no stacked sessions |
| P5 | Run Watch-first | Start outdoor run preferring Watch | Waits for running ack/mirror; summary only if reached active |

## Full reproduction matrix

Mark each row Pass / Fail / N/A. Prefer one clean Console log bundle per failure.

### Watch / connectivity

| Scenario | Pass? | Notes |
|----------|-------|-------|
| Watch open + reachable | | |
| Watch app closed | | |
| Watch locked / wrist down | | |
| Watch unreachable mid-start | | |
| WC not reachable at launch, Watch paired | | HealthKit launch attempt + durable prelaunch/ack |
| Watch force-quit then phone-started gym/run | | Cold launch can verify by mirror, ack, or Watch state |
| Watch airplane mode then reconnect during recovery | | One recovery cycle resends identity and retries launch |
| Bluetooth off then on | | |
| No paired Watch | | |

### iPhone lifecycle

| Scenario | Pass? | Notes |
|----------|-------|-------|
| iPhone foreground start | | |
| iPhone background during start | | |
| Force-quit iPhone mid-start, relaunch | | |
| Navigate away mid-start | | |
| After prior complete | | |
| After prior cancel | | |
| After prior fail / timeout | | |

### Workout types

| Scenario | Pass? | Notes |
|----------|-------|-------|
| Outdoor run | | |
| Indoor run / walk | | |
| Strength / free gym on Watch | | |
| Saved routine | | |
| Newly created routine | | |
| Old template routine | | |
| Sequential different types (gym → run → gym) | | |

### Stale / race conditions

| Scenario | Pass? | Notes |
|----------|-------|-------|
| Stale finished gym in cache, new Start | | |
| Delayed previous WC finished message | | |
| End from Watch | | |
| End from iPhone | | |
| Cancel before active | | |
| Late ack after timeout / iPhone fallback | | |
| Mirror before typed gym acknowledgement | | Matching request/session promotes live; mismatched mirror is rejected |

## Log signals to confirm

- `summaryPresentationBlocked` when Done would have been wrong
- `staleFinishedIgnored` on new gym start clearing finished cache
- `workoutActivated` / `markSessionReachedActive` before live UI
- `watchLaunchDecision` with `healthKit+durableWC` when WatchConnectivity is not reachable
- `watchPrelaunchDurablyQueued` for each gym prelaunch and acknowledgement
- `watchRecoveryAttempt` exactly once before final timeout
- `watchStartVerified` with `ack`, `mirror`, or `ackOrActiveState`
- `watchHealthKitMirroringStarted` precedes `watchHealthKitActivityStarted`
- `acknowledgeTerminal` after summary consume
- No `session.end` / teardown for unmatched mirrors without request/session identity

## Rollback

1. Kill-switch: `pulsar.feature.gymCrossDeviceStart` (keep Phase 1 UI guards even if ack path is disabled)
2. Do not remove lifecycle logging or consumed/eligibility session IDs
3. Preserve tombstones and finished-cache clear on new start

## Signoff

| Role | Name | Date | Result |
|------|------|------|--------|
| Engineering | | | |
| Device soak (iPhone + Watch) | | | |
