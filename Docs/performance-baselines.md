# Pulsar Performance Baselines

## Objective

Phase 0 establishes repeatable, privacy-safe performance baselines before remediation work changes Pulsar's behavior. Use these baselines to compare equivalent builds and journeys, not to infer a root cause from one trace.

Acceptance measurements come from optimized Release builds on physical devices. XCTest performance tests are useful regression signals, but the current `Pulsar` scheme runs tests in Debug and the Release app target does not enable testability. Simulator frame rates and Debug XCTest timings are therefore not substitutes for the physical-device Release results in this guide.

This phase is observability-only. Do not combine a baseline capture with a state-management, persistence, WatchConnectivity, HealthKit, or visual-performance fix.

## Supported project setup

- Project: `Pulsar.xcodeproj`
- Phone scheme: `Pulsar`
- Watch scheme: `Pulsar Watch App Watch App`
- Test target: `PulsarTests`
- Profile configuration: Release for both app schemes
- Phone deployment target: iOS 26.0
- Watch deployment target: watchOS 10.0
- Signpost subsystem: `tech.aetherial.pulsar`
- Signpost categories: `launch`, `wc`, `fitness`, `gym`, `run`, `muscle`, `catalog`, and `tab`

Release builds use `dwarf-with-dsym`. Keep the dSYMs produced by the exact build being profiled until the trace has passed the symbolication gate below.

## Privacy and handling rules

Instruments traces can contain process names, log metadata, timing, file paths, and health or workout context. Treat every trace as local sensitive diagnostic data.

- Never place raw HealthKit samples, GPS coordinates or routes, exercise notes, names, account identifiers, secrets, or request bodies in signpost metadata.
- Prefer counts, booleans, fixed reason codes, payload byte sizes, and coarse state names.
- Use a short capture-local correlation token when phone and Watch events must be matched. Do not put a stable user or device identifier in a committed summary.
- Keep device UDIDs, serial numbers, ECIDs, hostnames, and full `git status` output in the local run manifest only.
- Redact correlation tokens and user-derived values from screenshots or exported tables before sharing them.
- Store `.trace`, `.xcresult`, dSYM, memgraph, and raw export files under `build/performance-baselines/`. The repository ignores `build/`; it does not ignore `*.trace` everywhere.
- Commit only sanitized Markdown or CSV summaries.

## Local artifact layout

Create one immutable directory for each source state and capture session:

```sh
RUN_ID="$(date +%Y%m%d-%H%M%S)"
BASELINE_DIR="$PWD/build/performance-baselines/$RUN_ID"
DERIVED_DATA="$BASELINE_DIR/DerivedData"

mkdir -p \
  "$BASELINE_DIR/manifest" \
  "$BASELINE_DIR/traces/iphone" \
  "$BASELINE_DIR/traces/watch" \
  "$BASELINE_DIR/symbols" \
  "$BASELINE_DIR/exports" \
  "$BASELINE_DIR/screenshots"
```

Use names that identify the device class, journey, data state, and run number. For example:

```text
traces/iphone/iphone14promax-fitness-cached-swiftui-run-01.trace
traces/watch/watch-series7-mirrored-gym-poi-run-01.trace
exports/iphone14promax-cold-launch.csv
manifest/environment.txt
```

Do not overwrite a previous run or append before/after recordings to the same trace bundle. Separate trace files make source-state and symbol matching auditable.

## Preflight

Run from the repository root:

```sh
xcodebuild -version
xcodebuild -project Pulsar.xcodeproj -list
xcodebuild -project Pulsar.xcodeproj -scheme Pulsar -showdestinations
xcodebuild -project Pulsar.xcodeproj -scheme 'Pulsar Watch App Watch App' -showdestinations
xcrun xctrace list templates
xcrun xctrace list devices
xcrun devicectl list devices
```

The phone or Watch is ready only when it appears online in `xcrun xctrace list devices`. A device that is merely paired or listed by `xcodebuild -showdestinations` is not enough for an Instruments capture. Unlock both devices, enable Developer Mode, trust the Mac, open the Watch app once, and reconnect before continuing when a device appears under `Devices Offline`.

Set the build destination IDs locally from `-showdestinations`; do not commit them:

```sh
export IPHONE_UDID='<physical iPhone destination id>'
export WATCH_UDID='<physical Apple Watch destination id>'
```

Create the local environment manifest before building:

```sh
{
  date -u '+captured_at_utc=%Y-%m-%dT%H:%M:%SZ'
  git rev-parse HEAD
  git status --short
  xcodebuild -version
  xcrun xctrace list devices
} > "$BASELINE_DIR/manifest/environment.txt"
```

Do not describe a run as a clean-head baseline when `git status --short` is nonempty. A dirty run may still be useful, but its exact local source state must remain identifiable.

Before each comparable run:

1. Disable Low Power Mode and screen recording.
2. Record the battery band and thermal state; wait when the device is hot.
3. Keep display brightness, network path, device orientation, and Watch reachability consistent.
4. Complete permission prompts before recording unless first-run permission cost is the explicit journey.
5. Select the required history fixture and Fitness cache state.
6. Stop unrelated apps, Xcode previews, and other profiling sessions.
7. Confirm no workout is already active and verify which device owns the new HealthKit workout.

## Verified build and test invocations

The project, scheme, configuration, and destination syntax below were verified against Xcode 26.6. A baseline is not build-verified until each command completes against the source state recorded in its manifest.

Build the Release phone product, including its embedded Watch and widget dependencies:

```sh
xcodebuild \
  -project Pulsar.xcodeproj \
  -scheme Pulsar \
  -configuration Release \
  -destination "platform=iOS,id=$IPHONE_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  build
```

Build the Release Watch product after Instruments reports the Watch online:

```sh
xcodebuild \
  -project Pulsar.xcodeproj \
  -scheme 'Pulsar Watch App Watch App' \
  -configuration Release \
  -destination "platform=watchOS,id=$WATCH_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  build
```

Run the Phase 0 XCTest microbenchmarks alone, on a physical iPhone, with parallel execution disabled:

```sh
xcodebuild \
  -project Pulsar.xcodeproj \
  -scheme Pulsar \
  -configuration Debug \
  -destination "platform=iOS,id=$IPHONE_UDID" \
  -parallel-testing-enabled NO \
  -only-testing:PulsarTests/PulsarPerformanceTests \
  -resultBundlePath "$BASELINE_DIR/exports/PulsarPerformanceTests.xcresult" \
  test
```

Confirm the class identifier in Xcode's Test navigator if Xcode changes test-discovery naming. Do not run process-wide memory metrics alongside the full test suite.

The build commands verify compilation but do not install and start the profiled process. Use Xcode's Profile action for canonical device capture:

1. Select the `Pulsar` or `Pulsar Watch App Watch App` scheme.
2. Select the physical phone or Watch destination.
3. Choose **Product > Profile**.
4. Confirm the Instruments launch configuration is Release.
5. Choose the template and journey below.
6. Save the resulting trace into the corresponding local artifact directory.

For an already installed and manually launched Release phone build, this optional command records a focused runtime Time Profiler trace:

```sh
xcrun xctrace record \
  --template 'Time Profiler' \
  --device "$IPHONE_UDID" \
  --attach Pulsar \
  --time-limit 60s \
  --output "$BASELINE_DIR/traces/iphone/runtime-time-profiler-run-01.trace"
```

Increment the run number for every recording; `xctrace` refuses to overwrite an existing trace.

Use Xcode's Profile action, rather than command-line attach, for App Launch and Watch installation or launch.

## Signposts to capture

Filter the Points of Interest track to subsystem `tech.aetherial.pulsar`, then select the category and name below. The dotted value is shorthand used by this guide; the implementation emits the text before the dot as the category and the text after it as the signpost name.

| Shorthand | Category | Name | Journey or operation |
| --- | --- | --- | --- |
| `launch.root_init` | `launch` | `root_init` | Root state construction |
| `launch.home_useful` | `launch` | `home_useful` | First useful cached Home presentation |
| `launch.hk_sync` | `launch` | `hk_sync` | Initial app-entry HealthKit synchronization |
| `wc.decode` | `wc` | `decode` | WatchConnectivity payload decode |
| `wc.encode` | `wc` | `encode` | WatchConnectivity payload encode |
| `wc.apply` | `wc` | `apply` | Decoded state application |
| `fitness.week_fetch` | `fitness` | `week_fetch` | Fitness week view-model fetch |
| `fitness.hk_weekly` | `fitness` | `hk_weekly` | HealthKit weekly activity query |
| `fitness.runs_hydrate` | `fitness` | `runs_hydrate` | Cached run hydration |
| `fitness.history_init` | `fitness` | `history_init` | Gym history-store initialization |
| `gym.publish_state` | `gym` | `publish_state` | Gym state persist and publish path |
| `gym.rest_tick` | `gym` | `rest_tick` | Gym rest countdown tick |
| `run.process_locations` | `run` | `process_locations` | Location batch processing |
| `run.snapshot_publish` | `run` | `snapshot_publish` | Run snapshot publication |
| `muscle.map_prepare` | `muscle` | `map_prepare` | Muscle-map presentation preparation outside SwiftUI body evaluation |
| `catalog.load` | `catalog` | `load` | Exercise-catalog load |
| `tab.select` | `tab` | `select` | UIKit preselection callback to selected-tab binding application |
| `tab.root_selected` | `tab` | `root_selected` | Root selected-tab observation and synchronous handling |
| `tab.dest_body` | `tab` | `dest_body` | First destination-root body evaluation for a selection generation |
| `tab.dest_appear` | `tab` | `dest_appear` | First destination appearance event for a selection generation |
| `tab.dest_useful` | `tab` | `dest_useful` | Destination appearance to first useful content |
| `fitness.tab_refresh` | `fitness` | `tab_refresh` | Fitness tab refresh, including completion or cancellation |
| `tab.chrome_reconcile` | `tab` | `chrome_reconcile` | Bottom-chrome reconciliation attempt; count `duplicate=false` as effective work and `duplicate=true` as a coalesced/no-op attempt |
| `tab.wallpaper` | `tab` | `wallpaper` | Root wallpaper identity update to displayed layout |
| `tab.transition_done` | `tab` | `transition_done` | UIKit selection start to transition-coordinator completion when available, otherwise next-main-turn chrome reconciliation |

Signpost names must remain stable. Put a gym publish reason, payload size, fixture count, or cache state in privacy-safe metadata instead of creating dynamic signpost names.

Tab signposts use a process-local, monotonic selection generation to correlate the stages of one switch. A duplicate UIKit selection callback for the same source and destination inside the short deduplication window reuses that generation. Asynchronous display completions carry the exact token they began with so a late completion cannot close a newer switch to the same destination. Implicit destination correlation expires at `tab.transition_done`; later ordinary layout reconciliations use generation `0`, and non-appearance Fitness refreshes use no selection generation. The token is not a stable device, account, or session identifier. Tab metadata is limited to fixed tab/cache/outcome labels, booleans, and generation numbers. Redact generations from shared screenshots when they are not needed to explain the ordering.

## Capture workflows

Xcode 26.6 lists `App Launch`, `SwiftUI`, `Time Profiler`, `Animation Hitches`, `Allocations`, `Leaks`, `File Activity`, `Logging`, and `Power Profiler` templates. It does not list standalone templates named `Energy Log`, `Core Animation`, or `Points of Interest`.

When a workflow calls for SwiftUI plus Time Profiler or Points of Interest, start from the SwiftUI or Time Profiler template and add the other instrument from the Instruments Library. If combined instrumentation causes excessive overhead, record separate passes of the same scripted journey and compare only like-for-like traces.

### 1. App Launch — phone

Scheme: `Pulsar`  
Template: App Launch  
Primary interval: process launch to `launch.home_useful`, which closes when cached Home is first materialized under the splash. Measure visible interactivity separately in App Launch so the deliberate splash duration is not confused with root-construction cost.

Capture separate populations:

- Cold process launch: app installed and configured, process terminated, no reinstall.
- Warm launch: recent process termination with the same cached data state.
- First-install or permission launch: optional diagnostic population, never mixed with ordinary cold-launch results.

For each measured launch:

1. Return to the Home screen and terminate Pulsar.
2. Keep the same account, permissions, cache state, and network path.
3. Start the App Launch recording.
4. Stop after Home is visibly interactive and `launch.home_useful` has closed or fired.
5. Record whether HealthKit synchronization extended beyond first useful Home.

Collect at least 20 cold launches and 20 warm launches per acceptance device and source state. Discard a run only for a documented setup failure such as a permission alert, disconnected debugger, incoming call, thermal warning, or missing signpost.

### 2. Fitness first meaningful paint and scroll — phone

Scheme: `Pulsar`  
Templates: SwiftUI and Time Profiler, with Points of Interest added  
Primary intervals: `fitness.week_fetch`, `fitness.hk_weekly`, `fitness.runs_hydrate`, `fitness.history_init`, `muscle.map_prepare`

Record cached and cold week states separately:

1. Launch to stable Home and wait five seconds.
2. Begin recording.
3. Open Fitness once.
4. Stop the time-to-first-meaningful-content timer when the week summary and primary cards are usable, not when background route hydration eventually finishes.
5. Scroll the same section range down and back up three times at a consistent pace.
6. Open and dismiss the same detail sheet once.
7. Stop after visible work and signpost intervals settle.

Do not mix empty history, 20-session history, 80-session history, or route-heavy data in one result population. Record the fixture and route-count band in the manifest.

Inspect SwiftUI body-update counts for `PulsarRootView`, Fitness sections, muscle-map views, and workout cards. In Time Profiler, inspect main-thread inclusive stacks and actor hops during the same scripted actions.

### 2A. Primary tab-switch transition — phone

Scheme: `Pulsar`  
Templates: Animation Hitches, then SwiftUI with Time Profiler and Points of Interest added  
Primary intervals: `tab.select`, `tab.root_selected`, `tab.dest_body`, `tab.dest_useful`, `tab.chrome_reconcile`, `tab.wallpaper`, `tab.transition_done`, and `fitness.tab_refresh`

Capture warm and cold Fitness cache populations separately. Also keep an active-workout population separate from the no-workout population.

1. Launch to stable Home and wait five seconds.
2. Begin recording and execute 20 Home → Fitness → Food → Home cycles with a consistent one-second dwell. Do not open Lab or Cycle from the Plus cover.
3. In the cold-Fitness population, invalidate only the documented Fitness freshness state before each independent observation; do not mix the resulting switch with warm observations.
4. In the active-workout population, start and minimize one correctly owned workout, wait for stable live metrics, then repeat the same cycle.
5. Stop after the final destination is useful and all `fitness.tab_refresh` intervals have completed or cancelled.

Use the selection generation to group stages inside one process. `tab.transition_done` ends at the UIKit transition-coordinator completion when UIKit provides one; its fallback ends after the next-main-turn chrome reconciliation, so do not describe fallback samples as exact visual-transition duration. It never waits for HealthKit or Fitness content. `tab.dest_useful` measures the destination readiness path. Neither interval should be interpreted as cross-device latency.

Create a dedicated immutable artifact directory beneath the run directory:

```sh
TAB_DIR="$BASELINE_DIR/tab-switch"

mkdir -p \
  "$TAB_DIR/traces/animation-hitches" \
  "$TAB_DIR/traces/swiftui-time-profiler" \
  "$TAB_DIR/exports" \
  "$TAB_DIR/screenshots"

cp "$BASELINE_DIR/manifest/environment.txt" "$TAB_DIR/environment.txt"
```

Use names that preserve cache/workout population and run number without user-derived data:

```text
tab-switch/traces/animation-hitches/promotion-warm-no-workout-run-01.trace
tab-switch/traces/swiftui-time-profiler/promotion-cold-no-workout-run-01.trace
tab-switch/traces/animation-hitches/promotion-warm-active-workout-run-01.trace
tab-switch/exports/promotion-warm-no-workout-switches.csv
```

For an installed, manually launched Release build, the following optional commands create separate focused passes. Use Xcode's Profile action when attaching does not reproduce the canonical Release configuration.

```sh
xcrun xctrace record \
  --template 'Animation Hitches' \
  --device "$IPHONE_UDID" \
  --attach Pulsar \
  --time-limit 90s \
  --output "$TAB_DIR/traces/animation-hitches/promotion-warm-no-workout-run-01.trace"

xcrun xctrace record \
  --template 'SwiftUI' \
  --device "$IPHONE_UDID" \
  --attach Pulsar \
  --time-limit 90s \
  --output "$TAB_DIR/traces/swiftui-time-profiler/promotion-warm-no-workout-run-01.trace"
```

The command-line SwiftUI pass does not automatically guarantee the same custom instrument combination as a saved Instruments document. Record the exact included instruments in the manifest and compare only matching configurations.

Store sanitized per-selection observations using this schema; leave fields blank when the instrument does not export the corresponding value:

```text
run_number,selection_generation,from_tab,to_tab,cache_state,workout_state,select_ms,transition_done_ms,dest_useful_ms,chrome_reconcile_attempt_count,chrome_reconcile_effective_count,hitch_count,longest_hitch_ms,valid,exclusion_reason
```

Do not add measurements to the repository until the Release-device trace, source manifest, comparability, and symbolication gates pass. The instrumentation landing by itself establishes no before/after result.

### 3. Minimized outdoor run while browsing — phone

Scheme: `Pulsar`  
Templates: SwiftUI and Time Profiler, with Points of Interest added  
Primary intervals: `run.process_locations`, `run.snapshot_publish`, `wc.encode`, `wc.apply`

1. Establish one valid workout owner and start an outdoor run.
2. Wait until recording UI, elapsed time, and available live metrics are stable.
3. Minimize the workout.
4. Browse Home for 30 seconds, then switch Home/Fitness/Home using the same cadence.
5. Scroll the same Home range while at least three one-second workout ticks occur.
6. Return to the workout without finishing it during the measured interval.

Confirm that the trace covers real device HealthKit and location behavior. Simulator FPS is not an acceptance result.

### 4. Animation hitches — phone

Scheme: `Pulsar`  
Template: Animation Hitches

Use separate traces for these scripts:

- Ten Home/Fitness tab-switch cycles.
- Ten presentations and dismissals of one representative sheet.
- A fixed 30-second Fitness scroll covering the muscle map and workout history.
- A fixed 30-second live run HUD interaction.

Record hitched frames, hitch duration, display refresh class, and the action that was in flight. Use the Animation Hitches template as the primary Xcode 26.6 workflow; add a Core Animation instrument only if it is available in the Instruments Library and keep that configuration identical before and after.

### 5. Allocations, leaks, and memory settling — phone

Scheme: `Pulsar`  
Templates: Allocations and Leaks

Capture independently:

- Visit every primary tab, then repeat the tab cycle ten times.
- Start a gym workout, minimize it, resume it, finish it, and wait 30 seconds on the summary.
- Record a long outdoor run or a controlled long-running workout fixture, then finish and wait for persistence to settle.

In Allocations, mark generations before the repeated action, after the final action, and after the settling period. Report resident-memory start, peak, settled value, retained first-party object families, and whether the ten-cycle settled value stays within the acceptance budget. A rising allocation graph is not proof of a leak without retained-object or memory-graph evidence.

### 6. Mirrored gym rest and WatchConnectivity — phone and Watch

Schemes: `Pulsar`, then `Pulsar Watch App Watch App`  
Template: Time Profiler or Logging with Points of Interest added  
Primary intervals: `gym.publish_state`, `gym.rest_tick`, `wc.encode`, `wc.decode`, `wc.apply`

Phone and Watch are different processes on different devices. Instruments signpost intervals cannot begin on one process and end on the other.

1. Create one capture-local run token in both local manifests so the two trace files remain paired.
2. For end-to-end latency, open separate phone and Watch Instruments documents, start both recordings from the same countdown, and run one mirrored gym start, set completion, 60-second rest, resume, and finish.
3. Record UTC start time, workout owner, WC activation state, reachability, and transport for both processes.
4. Correlate individual events only with a privacy-safe session/request token that the app emits on both devices for that same workout. The manifest-only run token can pair traces, but cannot correlate individual signposts.
5. Confirm exactly one workout save and one summary path after the journey.

If the current instrumentation does not emit a shared per-event token, report only local encode, decode, apply, and UI-update intervals. If the local Instruments setup cannot record both devices concurrently, capture repeatable phone-only and Watch-only passes for local attribution. Do not calculate cross-device transfer or acknowledgement latency from different workout sessions.

Do not report an end-to-end phone-to-Watch interval by subtracting unmatched signposts unless clock alignment and correlation are explicit. Report local encode, transfer-observed, decode, apply, acknowledgement, and UI-update segments separately.

### 7. File activity — phone

Scheme: `Pulsar`  
Template: File Activity

Capture two focused traces:

- Fitness appearance with a declared gym/run history fixture and cache state.
- Gym finish through persistence completion and summary presentation.

Report main-thread file activity, repeated reads, bytes read/written, file or UserDefaults domain category, and the signpost interval in which the activity occurred. Sanitize exported paths before sharing.

### 8. Power — phone and Watch

Schemes: `Pulsar`, then `Pulsar Watch App Watch App`  
Template: Power Profiler

Xcode 26.6 names this template `Power Profiler`, not `Energy Log`.

Capture a 20-minute outdoor-run segment and a 20-minute gym segment under comparable battery, display, network, Watch reachability, and sensor conditions. Record the phone and Watch independently. Use these results as directional evidence; do not claim equivalence with Apple Fitness unless the activity, sensors, duration, device state, and measurement method are genuinely comparable.

## Run metadata template

Copy this block into the local manifest for every result population. Keep device identifiers and sensitive details local.

```text
run_id:
captured_at_utc:
git_commit:
working_tree: clean | dirty
local_source_manifest:
xcode_version:
swift_version:
scheme:
configuration: Release | Debug XCTest
template_and_instruments:
journey:
run_count:

device_role: phone | watch
device_model:
product_type:
os_version_and_build:
display_class: ProMotion | 60 Hz | watch
device_identifier_local_only:
paired_device_model:
paired_device_os:
instruments_online: yes | no

battery_band:
low_power_mode: on | off
thermal_state:
network_path:
watch_reachability:
device_orientation:
brightness_policy:

healthkit_permissions: configured | prompt included | unavailable
workout_owner:
history_fixture: empty | 20 gym | 80 gym | other
fitness_cache: cached | cold
route_data_band: none | typical | route-heavy
catalog_fixture:
correlation_token_local_only:

trace_path:
dsym_path:
binary_uuid:
dsym_uuid:
symbolication_gate: pass | fail
setup_failures_or_exclusions:
notes:
```

Do not include sample values, routes, exercise notes, user names, stable identifiers, or full local paths in a committed results table.

## Aggregation and comparison

Use one population only when all of these match: source state, scheme and configuration, device model, OS, display class, journey, fixture/cache state, Instruments configuration, network policy, and major power or thermal conditions.

For latency metrics:

1. Export or transcribe one duration per valid run in milliseconds.
2. Sort durations from lowest to highest.
3. Use the nearest-rank percentile: rank = `ceil(percentile × sample count)`.
4. Report sample count, p50, p95, minimum, maximum, and excluded-run count.
5. Require at least 20 comparable observations before reporting p95; 30 or more is preferred.

For 20 observations, p50 is the 10th sorted value and p95 is the 19th sorted value. Do not average per-run percentiles. Do not combine ProMotion and 60 Hz devices, cached and cold Fitness states, or phone and Watch process durations.

Store raw latency observations in a CSV with this schema:

```text
run_number,duration_ms,valid,exclusion_reason
1,1824.3,true,
2,0,false,permission prompt
```

The following command applies the documented nearest-rank method and excludes rows whose `valid` field is not `true`:

```sh
python3 - "$BASELINE_DIR/exports/latencies.csv" <<'PY'
import csv
import math
import sys

with open(sys.argv[1], newline="") as source:
    rows = list(csv.DictReader(source))

values = sorted(
    float(row["duration_ms"])
    for row in rows
    if row["valid"].strip().lower() == "true"
)
if not values:
    raise SystemExit("no valid duration_ms observations")

def nearest_rank(percentile):
    return values[math.ceil(percentile * len(values)) - 1]

print(f"n={len(values)}")
print(f"p50_ms={nearest_rank(0.50):.3f}")
print(f"p95_ms={nearest_rank(0.95):.3f}")
print(f"min_ms={values[0]:.3f}")
print(f"max_ms={values[-1]:.3f}")
print(f"excluded={len(rows) - len(values)}")
PY
```

For scroll and animation traces, report the tool's hitched-frame or hitch-rate metric plus total observed frames and capture duration. For memory, report start, peak, and settled values after the scripted settling period rather than averaging unrelated points in the allocation graph. For power, report each full segment and use medians only across truly comparable repeated segments.

Before/after comparison is valid only when the journey, build configuration, device/OS, data state, Instruments configuration, and run policy match. Report absolute values and deltas:

```text
delta_ms = after_ms - before_ms
delta_percent = ((after_ms - before_ms) / before_ms) * 100
```

Do not convert a low-sample observation into a pass/fail claim. Mark it exploratory and schedule a larger population.

## Symbolication gate

Do not interpret a first-party hotspot from an unsymbolicated trace.

After the Release build, locate the exact dSYMs. `$DERIVED_DATA` contains the command-line verification build used above:

```sh
find "$DERIVED_DATA/Build/Products" -type d -name '*.dSYM' -print
```

Verify that the app binary and dSYM UUIDs match. Example for the phone product:

```sh
APP="$DERIVED_DATA/Build/Products/Release-iphoneos/Pulsar.app"
DSYM="$DERIVED_DATA/Build/Products/Release-iphoneos/Pulsar.app.dSYM"

dwarfdump --uuid "$APP/Pulsar"
dwarfdump --uuid "$DSYM"
```

The corresponding Watch paths are quoted because the product name contains spaces:

```sh
WATCH_APP="$DERIVED_DATA/Build/Products/Release-watchos/Pulsar Watch App.app"
WATCH_DSYM="$DERIVED_DATA/Build/Products/Release-watchos/Pulsar Watch App.app.dSYM"

dwarfdump --uuid "$WATCH_APP/Pulsar Watch App"
dwarfdump --uuid "$WATCH_DSYM"
```

Copy the matching phone and Watch dSYM bundles into `$BASELINE_DIR/symbols/` before cleaning DerivedData.

**Product > Profile** may create a separate Release build in Xcode's configured DerivedData location. Use the dSYM from that Profile build, as shown in Xcode's Report navigator, rather than assuming the command-line verification dSYM matches. The UUID check is authoritative: if the UUID differs, locate and preserve the matching Profile-build dSYM before analyzing the trace.

When Instruments does not load a preserved matching dSYM automatically, open the saved trace, choose **File > Symbols**, select the unsymbolicated Pulsar binary, and load the matching dSYM. Reopen the call tree and reapply its filters before passing the gate.

A trace passes the gate only when:

- The profiled app UUID matches the preserved dSYM UUID.
- Time Profiler and SwiftUI call trees show Pulsar Swift type and function names, not only addresses or hex offsets.
- Meaningful first-party frames can be expanded through the call tree.
- The trace records the expected process and Release configuration.

System-framework frames without private Apple symbols are expected. Missing symbols for the Pulsar app or other first-party binaries invalidate hotspot attribution; rebuild or re-symbolicate and capture again.

## Sanitized results template

Keep the raw run manifest locally. Commit only a table like this after the symbolication and comparability gates pass:

| Date | Source state | Device class | OS | Journey/data state | Runs | Metric | p50 | p95 | Budget | Result | Trace location |
| --- | --- | --- | --- | --- | ---: | --- | ---: | ---: | --- | --- | --- |
| YYYY-MM-DD | commit, clean/dirty | ProMotion phone | iOS x.y | cold launch, configured | 20 | launch to useful Home | — | — | 1.8s / 2.5s | pending | local-only run ID |
| YYYY-MM-DD | commit, clean/dirty | 60 Hz phone | iOS x.y | cached Fitness | 20 | first meaningful paint | — | — | 400ms | pending | local-only run ID |

For hitch, memory, file activity, and power captures, replace p50/p95 with the relevant aggregate and include the observation duration or cycle count in the journey column.

## Current device limitations

Inventory verified on 2026-07-12. Current preflight output is authoritative because connectivity, device inventory, and OS versions can change.

The verified local inventory at the start of Phase 0 provides:

- A connected iPhone 14 Pro Max on iOS 26.5.2, covering the ProMotion acceptance class.
- A paired Apple Watch Series 7 on watchOS 26.5. At inspection time it appeared available to device tooling but under `Devices Offline` in `xcrun xctrace list devices`; Watch Instruments captures are blocked until it appears online there.
- No physical 60 Hz iPhone visible to Xcode/Instruments. All 60 Hz acceptance rows must remain pending until such a device is available.

Do not substitute a simulator or a ProMotion device capped in software for the missing physical 60 Hz acceptance pass. Those runs may be retained as exploratory evidence but must be labeled accordingly.

## Tab-switch implementation verification — 2026-07-14

This verification was run from a dirty local source state containing the tab-switch work plus pre-existing workout, Watch, route, and muscle-map changes. It is not a clean-commit benchmark. Raw products, result bundles, and attempted trace artifacts remain under ignored `build/performance-baselines/` directories.

| Gate | Environment | Result | Local artifact |
| --- | --- | --- | --- |
| Preserved pre-change phone build | Release, physical iPhone 14 Pro Max, iOS 26.5.2 | Passed | `20260712-tab-switch-physical-release/before/derived-data` |
| Final phone build | Clean Release build, same physical iPhone | Passed | `20260714-tab-switch-physical-release/after/derived-data` |
| Final simulator build | Clean Release build, iPhone 17 Pro simulator, iOS 26.5 | Passed | `20260714-tab-switch-physical-release/after/simulator-derived-data` |
| Targeted regression matrix | Debug XCTest, physical iPhone, parallel testing disabled | 80 passed, 0 failed, 0 skipped | `20260714-tab-switch-physical-release/test-results/targeted-matrix-launchfix.xcresult` |
| Release launch gate | Physical phone and iOS simulator | Full Home remained rendered beyond the previous 20-second watchdog window | Release products above |

The targeted matrix covers tab-selection token/deduplication and active-correlation expiry, Fitness single-flight/priority ordering and warm-maintenance coalescing, warm week/progress caches, rollover shutdown, mini-player metric policy plus narrow local-gym elapsed/content updates, bottom-chrome no-op publications and pixel quantization, workout-start ownership phases, completion presentation, and cross-device gym-start coordination.

One console-attached physical launch printed a single AttributeGraph cycle diagnostic. Unlike the pre-fix feedback loop, it did not repeat or trigger the 20-second watchdog, and the app remained fully rendered. The simulator unified log contained no AttributeGraph cycle entry throughout the no-workout, active-workout, and completion runs.

The hosted test target originally launched the complete production root before the XCTest worker could materialize. `PulsarApp` now detects `XCTestConfigurationFilePath`, skips production launch services, and mounts an empty host scene only for unit-test processes. The final post-launch-fix matrix completed all 80 tests on the physical phone. Runner duration is not a product performance measurement.

The Release binary/dSYM symbol UUID gate passed for the preserved products:

- Before: `F135F999-0276-3B3A-9662-DD9F300F2262`
- After physical device: `807D6D93-2079-3E7A-AD1D-064A016EA0BF`
- After simulator: `841FF505-EBA1-3E7B-B7F6-DE35F3D430E5`

The final builds still emit existing Swift 6 migration warnings in `PulsarRunRouteFileStore` and `PulsarWorkoutRouteCapture`; the tab-switch changes add no Release warning.

### Matched physical-device runtime traces

The valid before and after traces use the same iPhone 14 Pro Max, Release configuration, warm no-workout state, and scripted Home → Fitness → Food → Home journey. Each pass contains 20 cycles and 60 selections. One earlier nine-selection SwiftUI recording is explicitly named `invalid-user-interruption` and is excluded.

| Instrument/export | Before | After | Interpretation |
| --- | ---: | ---: | --- |
| Animation Hitches `hitches` rows, 700 ms pacing | 0 | 0 | No hitch row in either matched 20-cycle exploratory trace |
| SwiftUI-template `hitches` rows, 650 ms pacing | 0 | 0 | No hitch row in either matched trace |
| SwiftUI-template `potential-hangs` rows | 0 | 0 | No potential-hang row in either matched trace |
| Low-level `swiftui-updates` rows | 1,004,165 | 657,725 | 346,440 fewer rows, a 34.5% reduction |
| Filtered `View Body Updates` rows | 191 | 212 | The view tree changed; do not treat this count alone as a regression or improvement |

The filtered body table moved work away from the three per-tab wallpaper bodies (`FitnessWeeklyBackground`, `NutritionBackground`, and `StaticTimeBackground*` no longer appear in the after table). The new small `MuscleBodyAlignedImage` subview accounts for most after body rows. The aggregate SwiftUI update table and zero-hitch result are the useful comparison; the body-row count is retained so the changed view decomposition is not hidden.

Physical trace locations:

- Before Animation Hitches: `20260712-tab-switch-physical-release/before/traces/animation-hitches/promotion-warm-no-workout-run-01.trace`
- After Animation Hitches: `20260714-tab-switch-physical-release/after/traces/animation-hitches/promotion-warm-no-workout-run-01.trace`
- Before SwiftUI: `20260712-tab-switch-physical-release/before/traces/swiftui-time-profiler/promotion-warm-no-workout-run-01.trace`
- After SwiftUI: `20260714-tab-switch-physical-release/after/traces/swiftui-time-profiler/promotion-warm-no-workout-run-01.trace`

Side-by-side Home and Fitness screenshots show no missing layer, layout shift, card/chrome regression, or muscle-asset alignment change. The muscle silhouettes are intentionally slightly crisper after removing a redundant runtime blur pass; labels, hierarchy, colors, and the premium card treatment remain intact.

This is one paired physical trace per source state. The zero-hitch and update-count comparison is exploratory, not a multi-run p95 acceptance claim.

### Simulator signpost verification

Remaining UI-driven validation moved to an iPhone 17 Pro simulator on iOS 26.5. Simulator results validate lifecycle and instrumentation behavior but do not replace physical-device frame-rate acceptance.

Both signpost populations contain 20 Home → Fitness → Food → Home cycles, 60 selections, 820 tab events, 380 fully paired intervals, and zero unclosed intervals. Percentiles use the documented nearest-rank method.

| Metric | Warm, no workout p50 / p95 | Warm, active gym p50 / p95 | Samples |
| --- | ---: | ---: | ---: |
| Tap → root selected | 2.747 / 3.574 ms | 2.726 / 3.691 ms | 60 each |
| Tap → destination appearance | 15.609 / 18.829 ms | 15.596 / 19.354 ms | 60 each |
| Tap → useful destination | 18.178 / 32.033 ms | 17.204 / 31.562 ms | 60 each |
| Tap → useful Fitness | 29.789 / 32.817 ms | 29.747 / 32.324 ms | 20 each |
| Tap → useful Food | 14.197 / 16.119 ms | 14.951 / 16.052 ms | 20 each |
| Tap → useful Home | 18.178 / 19.662 ms | 17.204 / 20.534 ms | 20 each |

Every population recorded exactly 60 `chrome_reconcile` attempts, 60 effective intervals, and zero duplicate/coalesced intervals: one effective reconciliation per selection. The reconciliation work itself had a no-workout p95 of 1.334 ms.

`tab.wallpaper` settles at p95 259.244 ms without a workout and 259.715 ms with one, matching the deliberate crossfade. `tab.transition_done` closes at p95 702.051 ms and 701.251 ms respectively because UIKit supplied its native transition completion; it is not tap-to-content latency. The destination was already useful at the values above.

Ten additional warm Fitness returns produced ten correlated `fitness.tab_refresh` intervals and ten completed outcomes. The first stale-aware refresh took 23.541 ms. The following nine non-stale returns took 0.014–0.021 ms, demonstrating that warm reappearance no longer clears and rebuilds the caches.

The active-workout population used an isolated simulator free-gym workout. Live elapsed time and heart rate updated in the minimized mini-player during all 60 selections. Finishing followed one completion-summary path, removed the mini-player, and refreshed Fitness to “Workout logged this week.” Targeted ownership/completion tests provide the duplicate-save regression coverage.

Simulator exports are local-only under:

- `20260714-tab-switch-physical-release/after/simulator/traces/signposts/promotion-warm-no-workout-switches.csv`
- `20260714-tab-switch-physical-release/after/simulator/traces/signposts/promotion-warm-no-workout-summary.csv`
- `20260714-tab-switch-physical-release/after/simulator/traces/signposts/promotion-warm-active-workout-switches.csv`
- `20260714-tab-switch-physical-release/after/simulator/traces/signposts/promotion-warm-active-workout-summary.csv`
- `20260714-tab-switch-physical-release/after/simulator/traces/signposts/fitness-warm-reappear-refreshes.csv`

### Coverage limits

The completed evidence covers the Phase 1–3 implementation, matched warm physical hitches/SwiftUI behavior, simulator warm/no-workout and active-workout signposts, and the targeted regression matrix. Physical cold-Fitness p95, physical active-workout hitches, Allocations/settled memory, a physical 60 Hz phone, and online Watch Instruments remain separate device-matrix work. An optional simulator RSS pass was interrupted by a locked Mac and is excluded rather than reported. No number is fabricated for those populations.

## Completion checklist

Phase 0 baseline capture is complete only when:

- The source state and local environment manifest are preserved.
- Release phone traces cover launch, Fitness, active-workout browsing, hitches, allocations/leaks, file activity, and power.
- Mirrored workout traces cover both phone and Watch processes, or the Watch limitation is explicitly marked blocked.
- ProMotion and 60 Hz result populations are complete, or the unavailable device class is explicitly pending.
- Every analyzed first-party trace passes the symbolication gate.
- p50/p95 values use comparable populations with at least 20 runs where p95 is reported.
- XCTest microbenchmarks run alone with parallel testing disabled and are labeled Debug regression signals.
- Raw traces remain under ignored local artifacts and committed summaries contain no sensitive health, route, device, or account data.
- Workout ownership, Watch start/finish, HealthKit persistence, route persistence, and duplicate-save behavior were observed for regressions during workout journeys.
