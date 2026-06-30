# Pulsar Codex Workflow

This workflow keeps Codex grounded in current tools, current documentation, and Pulsar-specific invariants.

## MCP Setup

- Xcode MCP is expected from the user-level Codex config via `xcrun mcpbridge`. Use it first for Apple docs, Xcode project inspection, builds, previews, diagnostics, and tests.
- `openaiDeveloperDocs` is configured in `.codex/config.toml` for current OpenAI API, model, Responses API, tool-calling, and Codex documentation.
- `context7` is configured in `.codex/config.toml` for current third-party library documentation. Prefer Apple/OpenAI official docs for Apple/OpenAI APIs.
- `github` is configured in `.codex/config.toml` for PRs, issues, and repository metadata. It requires `GITHUB_PAT_TOKEN` in the environment and should prompt before tool actions.

After changing MCP config, restart Codex or open a new thread and run `/mcp` or `codex mcp list` to confirm the servers are visible.

## Coding Loop

1. Inspect the local code first: relevant Swift files, shared models, tests, docs, and Xcode diagnostics.
2. For new or fast-moving APIs, verify current docs before implementing:
   - Apple/Xcode docs for SwiftUI, Liquid Glass, HealthKit, WidgetKit, ActivityKit, WatchConnectivity, App Intents, and Foundation Models.
   - OpenAI Docs MCP for Orion/OpenAI API behavior, model choices, Responses API, tool calling, structured outputs, and prompt upgrades.
   - Context7 only when official Apple/OpenAI docs are not the right source.
3. Make the smallest coherent code change that fits existing Pulsar patterns.
4. For nontrivial SwiftUI changes, run a modernity pass before verification: avoid deprecated navigation, lifecycle, observation, layout, and animation patterns; check state ownership, accessibility, and performance; and use `swiftui-pro` when available as a second-pass reviewer.
5. Verify with the narrowest useful checks: Xcode build, targeted tests, previews, simulator checks, or specific diagnostics for the touched feature.
6. Review the final diff for regressions, privacy issues, duplicated workout saves, stale WatchConnectivity state, unsupported OS/API usage, and accidental broad rewrites made only for style.

## Subagents

Use subagents only when their work can be separated cleanly:

- Use read-only explorer agents for independent research, codebase mapping, log analysis, or test-gap review.
- Use worker agents only with disjoint file ownership. Tell them they are not alone in the codebase and must not revert unrelated changes.
- Avoid parallel write-heavy work on the same SwiftUI views, Xcode project file, shared models, or generated assets.
- Ask subagents for distilled findings with file references, not raw logs.

## Prompt Shape

Good Pulsar implementation prompts include:

- Goal: the user-visible behavior or bug fix.
- Context: files, screens, logs, screenshots, or failing tests.
- Constraints: OS targets, Liquid Glass expectations, AI/privacy boundaries, HealthKit ownership, WatchConnectivity behavior.
- SwiftUI bar: whether the change needs `swiftui-pro` or another modern SwiftUI review pass before final verification.
- Done when: the build/test/preview/simulator condition that proves the change.

## AI And Privacy Checks

- Orion requests must use summarized Pulsar context, not raw HealthKit samples, full local databases, browser state, or secrets.
- OpenAI API keys, model selection, tool routing, web search, and provider policy stay server-side.
- Keep mock/simulator behavior available for local development.
- Treat medical and fitness guidance as trend explanation and coaching support, not diagnosis.
