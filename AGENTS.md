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
- Use `swiftui-pro` from Twostraws' SwiftUI Agent Skill when available or explicitly requested as a modern SwiftUI review pass for nontrivial SwiftUI code. It should catch deprecated APIs, weak data flow, navigation issues, accessibility gaps, and performance risks, while preserving Pulsar's local patterns and supported OS targets.
- Use `openai-docs` when changing Orion/OpenAI API usage, model selection, Responses API behavior, tool calling, prompting, or AI backend contracts.
- Use `computer-use` when Xcode, Simulator, watchOS, device permissions, or visual UI inspection requires operating the local Mac UI.
- Use `imagegen` only for bitmap assets such as app icons, onboarding art, device imagery, branded empty states, or visual mockups.
- Use `doc-coauthoring` for product specs, architecture notes, release notes, HealthKit data contracts, scoring-model explanations, and handoff docs.
- Use `skill-creator` when improving this project guidance or creating a dedicated Pulsar workflow skill.

## Skills To Treat As Opt-In

Do not use unrelated document, web, data, presentation, deployment, or general creative skills for this project unless the user explicitly asks for that artifact or workflow. This includes `webapp-testing`, `web-artifacts-builder`, `browser-use`, `chrome`, `spreadsheets`, `xlsx`, `documents`, `docx`, `pdf`, `presentations`, `pptx`, `algorithmic-art`, `canvas-design`, `slack-gif-creator`, `theme-factory`, `brand-guidelines`, `internal-comms`, and `mcp-builder`.

## Codex Workflow Discipline

- Default loop: inspect the relevant files, check Apple/Xcode docs when APIs may have changed, make the smallest coherent change, build with Xcode MCP, then run targeted tests.
- For nontrivial SwiftUI changes, include a modernity pass before finalizing: prefer current SwiftUI APIs supported by Pulsar's targets, avoid deprecated patterns, check state ownership/navigation/accessibility/performance, and use `swiftui-pro` when available to review the final approach.
- Prefer `rg` and Xcode MCP searches scoped to `Pulsar/`, `Shared/`, `Pulsar Watch App Watch App/`, `PulsarWidgetsExtension/`, `PulsarWidgetShared/`, and `PulsarTests/`.
- Follow `Docs/codex-workflow.md` for the durable Pulsar coding loop, MCP usage, subagent usage, and prompt shape.
- Use project MCPs from `.codex/config.toml` when available: `openaiDeveloperDocs` for OpenAI/Codex docs, `context7` for current third-party docs, and `github` for PRs/issues/repository metadata. Prefer Xcode/Apple docs for Apple APIs.
- Use Context7 only for third-party library/package documentation; prefer Xcode/Apple docs for Apple APIs and OpenAI Docs MCP for OpenAI/Codex/API behavior.
- Use GitHub MCP only when PRs, issues, Actions, releases, or repository metadata are directly relevant. Require confirmation before mutating GitHub state.
- Avoid scanning generated output. `build/`, `DerivedData/`, `.xcresult`, and user-specific Xcode state are local artifacts, not source context.
- Treat HealthKit workout ownership as a first-class invariant. Before changing workout flows, trace UI -> session state -> HealthKit/WatchConnectivity -> persistence -> Activity Log and check for duplicate saves or stale-session alerts.
- Treat WatchConnectivity as opportunistic. Guard sends with activation/reachability where appropriate, keep application context for latest state, and use queued transfers only for state that must eventually arrive.
- Use Liquid Glass APIs only behind availability checks and only where they improve a concrete SwiftUI surface. Keep grouped glass effects in containers for rendering performance.

## Modern Swift And API Freshness

- Treat SwiftUI, Liquid Glass, Observation, Swift Concurrency, HealthKit, WidgetKit, ActivityKit, WatchConnectivity, App Intents, Foundation Models/Apple Intelligence, and OpenAI APIs as fast-moving areas. When a task mentions latest/current/new APIs, iOS 26+, Liquid Glass, AI, model upgrades, tool calling, or Apple Intelligence, verify current official Apple or OpenAI documentation before implementing.
- Prefer the current Swift API Design Guidelines and established local patterns over generic style advice. Keep naming call-site friendly, avoid unnecessary abstraction, and preserve existing domain language for workouts, recovery, nutrition, Orion, and widgets.
- For SwiftUI generation or refactors, treat stale examples as suspect: avoid old navigation, lifecycle, observation, layout, and animation patterns when modern equivalents are supported. If `swiftui-pro` suggests a newer API, verify availability and fit before adopting it.
- Use availability gates for new Apple APIs and keep useful fallbacks for earlier supported OS versions. Do not let iOS 26+ polish break current iOS/watchOS/widget behavior.
- When docs or SDK behavior are uncertain, state the uncertainty, cite the source checked when relevant, and keep the change narrow enough to revise safely.

## Liquid Glass Guidance

- For Liquid Glass tasks, load `swiftui-liquid-glass` and prefer native SwiftUI APIs such as `glassEffect`, `GlassEffectContainer`, `glassEffectID`, and `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` over custom blur/material imitations.
- Apply glass after layout and visual modifiers, group multiple glass elements in `GlassEffectContainer`, and use `.interactive()` only for tappable, focusable, or pointer-reactive surfaces.
- Use Liquid Glass where it clarifies app chrome, controls, sheets, dashboard affordances, or Orion entry points. Avoid turning dense health data, workout controls, or watch surfaces into low-contrast decoration.
- Keep shape, tint, spacing, motion, accessibility contrast, and Reduce Transparency fallbacks coherent with the surrounding Pulsar UI.

## AI And Orion Guidance

- Before changing Orion or AI features, read `Docs/orion-ai-assistant.md` plus the relevant Orion service, context, view model, and backend/proxy files.
- Keep `OPENAI_API_KEY`, model selection, provider routing, tool calling, web search, logging policy, and secret handling server-side. The iOS app should only know the trusted Orion backend URL and request contract.
- For OpenAI Responses API, model names, structured outputs, tool calling, realtime/audio, or prompt upgrades, verify current OpenAI documentation instead of relying on memory. Preserve explicit user-selected models unless the user asks for an upgrade.
- Send summarized Pulsar context, not raw HealthKit samples, full local databases, secrets, or unnecessary personal data. Keep medical language cautious: Orion can explain trends and missing data, but must not diagnose.
- When adding AI capabilities, prefer typed request/response contracts, robust error decoding, mock/simulator paths, and targeted tests around privacy, configuration, and failure states.

## Swift Code Quality

- Favor small Swift types with clear ownership, `Sendable` where it matters, explicit actor/main-thread boundaries for UI-facing state, and async work that can be cancelled or safely ignored when views disappear.
- Do not introduce SwiftLint, SwiftFormat, or broad formatting churn without explicit user approval. If those tools are added later, start with a gradual config that protects correctness without rewriting the whole project.
- Keep previews, fixtures, and tests aligned with the touched feature. Prefer focused tests for scoring logic, Orion contracts, HealthKit transforms, duplicate-workout guards, and WatchConnectivity state reconciliation.

## Subagent Guidance

- Use subagents for independent read-heavy research, codebase mapping, log/test analysis, or clearly separated implementation slices.
- Avoid parallel write-heavy work on the same files. When a worker edits code, give it explicit file/module ownership and require a final list of changed paths.
- Keep the main thread responsible for integrating results, checking diffs, and preserving user changes.

## Verification Bias

Prefer narrow Xcode builds, targeted tests, previews, and simulator checks that match the touched files. Avoid broad refactors or unrelated generated-file churn.
