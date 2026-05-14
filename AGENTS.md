# Pulsar Codex Guidance

Pulsar is a SwiftUI Apple-platform app covering iOS, watchOS, widgets, HealthKit, WatchConnectivity, ActivityKit, and local test targets.

## Preferred Skills And Tools

- Use Xcode MCP tools first for Apple documentation, project structure, builds, diagnostics, previews, and tests.
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

## Verification Bias

Prefer narrow Xcode builds, targeted tests, previews, and simulator checks that match the touched files. Avoid broad refactors or unrelated generated-file churn.
