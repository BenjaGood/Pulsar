# Pulsar Codex Guidance

Pulsar is a SwiftUI Apple-platform app covering iOS, watchOS, widgets, HealthKit, WatchConnectivity, ActivityKit, and local test targets.

## Preferred Skills And Tools

- Use Xcode MCP tools first for Apple documentation, project structure, builds, diagnostics, previews, and tests.
- Keep the active Codex working set lean. Start from the code and Xcode diagnostics, then load only the one or two skills that directly match the task.
- Use the installed iOS skills when they match the task:
  - `swiftui-ui-patterns` for SwiftUI UI implementation and platform conventions.
  - `swiftui-view-refactor` for splitting or stabilizing large SwiftUI views.
  - `swiftui-performance-audit`, `ios-ettrace-performance`, and `ios-memgraph-leaks` for performance or memory work.
  - `ios-debugger-agent` for simulator/debugging workflows.
  - `ios-app-intents` for App Intents, shortcuts, Spotlight, and system surfaces.
  - `swiftui-liquid-glass` only when adopting or reviewing iOS 26+ Liquid Glass APIs.
- Use `computer-use` when Xcode, Simulator, watchOS, device permissions, or visual UI inspection requires operating the local Mac UI.
- Use `frontend-design` for product-quality SwiftUI polish, visual hierarchy, interaction states, dashboards, cards, and watch UI density.
- Use `imagegen` only for bitmap assets such as app icons, onboarding art, device imagery, branded empty states, or visual mockups.
- Use `doc-coauthoring` for product specs, architecture notes, release notes, HealthKit data contracts, scoring-model explanations, and handoff docs.
- Use `skill-creator` when improving this project guidance or creating a dedicated Pulsar workflow skill.

## Skills To Treat As Opt-In

Do not use unrelated document, web, data, presentation, deployment, or general creative skills for this project unless the user explicitly asks for that artifact or workflow. This includes `webapp-testing`, `web-artifacts-builder`, `browser-use`, `chrome`, `spreadsheets`, `xlsx`, `documents`, `docx`, `pdf`, `presentations`, `pptx`, `algorithmic-art`, `canvas-design`, `slack-gif-creator`, `theme-factory`, `brand-guidelines`, `internal-comms`, and `mcp-builder`.

## Codex Workflow Discipline

- Default loop: inspect the relevant files, check Apple/Xcode docs when APIs may have changed, make the smallest coherent change, build with Xcode MCP, then run targeted tests.
- Prefer `rg` and Xcode MCP searches scoped to `Pulsar/`, `Shared/`, `Pulsar Watch App Watch App/`, `PulsarWidgetsExtension/`, `PulsarWidgetShared/`, and `PulsarTests/`.
- Avoid scanning generated output. `build/`, `DerivedData/`, `.xcresult`, and user-specific Xcode state are local artifacts, not source context.
- Treat HealthKit workout ownership as a first-class invariant. Before changing workout flows, trace UI -> session state -> HealthKit/WatchConnectivity -> persistence -> Activity Log and check for duplicate saves or stale-session alerts.
- Treat WatchConnectivity as opportunistic. Guard sends with activation/reachability where appropriate, keep application context for latest state, and use queued transfers only for state that must eventually arrive.
- Use Liquid Glass APIs only behind availability checks and only where they improve a concrete SwiftUI surface. Keep grouped glass effects in containers for rendering performance.

## Verification Bias

Prefer narrow Xcode builds, targeted tests, previews, and simulator checks that match the touched files. Avoid broad refactors or unrelated generated-file churn.
