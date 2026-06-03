# Pulsar Nutrition Implementation Log

Date: 2026-05-23

## Phase 0: Research And Planning

- Created `MyFitnessPal_Feature_Audit_For_Pulsar.md` from a live iPhone Mirroring walkthrough.
- Kept the audit focused on functional patterns and user flows, not brand, exact copy, visual layout, or proprietary design.
- Redacted personal account details and body metrics observed during the walkthrough.
- Treated barcode and meal photo capture as permission/camera-gated flows. iPhone Mirroring cannot expose the iPhone camera to the Mac, so scanner behavior was documented from the permission/scanner/manual-entry/onboarding states.
- Confirmed Pulsar should not clone a calorie-led app structure. The proposed direction is a Pulsar-native nutrition ecosystem centered on recovery-aware nourishment, fast logging, daily rhythm, hydration, body trends, and elegant insights.
- No Pulsar source code has been changed in this phase.

## Initial Product Decisions

- Nutrition should feel integrated with existing Pulsar health surfaces rather than become a separate utility app.
- Calories should be supported but not become the emotional center of the experience.
- Food capture should always include editable confirmation when using barcode, image, voice, or AI-assisted parsing.
- Logging should be fast enough for repeated daily use, but the UI should remain calm, sparse, and Liquid Glass-native.
- All future implementation must preserve the existing tab bar and avoid regressions to Fitness, Mindfulness, Lab, Cycle, Oura, and Apple Watch functionality.

## Pending Before Code

- Sub-agent category plans.
- Consolidated Pulsar Nutrition master plan.
- User review of audit summary, feature list, proposed Pulsar feature set, and implementation order.
- Explicit approval before source-code implementation begins.

## Sub-Agent Collaboration Summary

All ten planning agents completed in read-only mode. No Pulsar source code was modified.

### Agent Decisions

- Agent 1, Food Diary: Nutrition should center on `Daily Fuel`, a calm day timeline with meal moments, a nourishment halo, editable food entries, and gentle repeat suggestions.
- Agent 2, Food Capture: Food entry should use one `Fuel Capture` command sheet for search, scan, estimate, create, and saved/private foods. Confidence and provenance must be visible.
- Agent 3, Targets: Goals should become recovery-aware ranges with daily target snapshots, not static calorie math. Use fuel range, protein anchor, macro balance, and nutrient priorities.
- Agent 4, Meals/Recipes/Templates: Build a private reusable nutrition memory system: meal templates, recipe studio, week plan, and sparse nourish ideas. Do not build a content-feed clone.
- Agent 5, Body/Hydration/Progress: Hydration and body metrics should be quiet trend signals with weekly-first body check-ins, smoothed trends, and HealthKit provenance.
- Agent 6, Exercise/HealthKit: Nutrition must consume workout/activity context from Fitness, HealthKit, Oura, and Apple Watch. It must not become a second exercise logger.
- Agent 7, Reminders: Build compassionate rhythm check-ins and context-aware reminders using Pulsar's existing intelligent notification architecture. Avoid punitive streak mechanics.
- Agent 8, Insights: Premium nutrition should be a thoughtful intelligence layer: daily coach brief, weekly nutrition rewind, trend constellation, and small experiments.
- Agent 9, Settings/Sync: Superseded by the user's implementation scope correction. Do not add Settings, profile, account, global preferences, or device-management surfaces for this phase.
- Agent 10, UI System: Build the Pulsar Nutrition design system first: reusable Liquid Glass cards, metric chips, command sheets, meal capsules, state views, and accessibility rules.

### Consolidated Product Direction

The merged plan is a Pulsar-native Nutrition system with five top-level pillars:

1. `Nutrition Today`: nourishment halo, meal rhythm, hydration, activity/recovery context, and daily coach brief.
2. `Daily Fuel Timeline`: meal moments as elegant glass capsules with editable entries and repeat suggestions.
3. `Fuel Capture`: search, scan, estimate, private foods, saved meals, water, weight, and future voice/plate capture.
4. `Nutrition Intelligence`: weekly rewind, trends, source-aware insights, and optional coaching experiments.
5. `Nutrition Library`: private foods, reusable templates, recipe studio, source provenance, and local-first nutrition memory.

### Architecture Decisions

- Start local-first with Codable stores behind protocols, matching current Pulsar patterns and preserving future migration options.
- Store source provenance and confidence on every user-entered, imported, scanned, estimated, or HealthKit-synced nutrition value.
- Persist daily target snapshots so historical diary days compare against their original targets.
- Use existing Fitness, HealthKit, Oura, and Watch systems as data sources. Do not duplicate workout records or create parallel WatchConnectivity channels.
- Keep HealthKit nutrition write-back off by default until local diary behavior is stable and duplicate-prevention metadata exists.
- Use AI later as an optional explanation/ranking layer, not as a dependency for first useful behavior.

### UX Decisions

- Preserve the existing tab bar and Pulsar visual identity.
- Use Liquid Glass for functional surfaces, not decoration.
- Avoid calorie shaming, punitive streaks, moralizing food language, or "earn food through exercise" mechanics.
- Use permission explainers before camera, microphone, HealthKit nutrition, and photo access.
- Every major surface must support empty, partial, filled, loading, error, permission-missing, completed, and low-confidence states.
- Motion should be subtle: matched transitions, numeric count-up, soft halo movement, and haptics on meaningful saves. Reduced Motion must be respected.

## Scope-Corrected Master Implementation Order

1. Build the shared Nutrition design system and mock-backed `Nutrition Today` shell.
2. Add core local models: nutrients, servings, meal moments, food entries, hydration entries, body measurements, target snapshots, source provenance.
3. Add protocol-backed local stores and mock fixtures.
4. Build `Daily Fuel Timeline` with meal moments, entry capsules, empty/filled states, and edit/delete/move/duplicate actions.
5. Build `Fuel Capture` sheet with mock search, quick estimate, private food creation, and confirmation preview.
6. Add hydration quick-add and body check-in flows with local persistence.
7. Add recovery-aware targets and daily target snapshot persistence.
8. Add Nutrition Library: private foods, meal templates, recipe studio, and save-as-template from diary.
9. Add activity context bridge from existing Fitness/HealthKit/Oura/Watch sources.
10. Add Nutrition Intelligence: daily coach brief, weekly rewind, trend cards, evidence sheets, and coaching experiments.
11. Add HealthKit nutrition/body/hydration sync later in scoped nutrition-only stages.
12. Add tests, previews, accessibility review, reduced-motion QA, and regression checks across existing Pulsar modules.

## Phase 1: Focused Nutrition Implementation

- Applied the user's scope correction: implemented only nutrition-specific features inside the existing Food/Nutrition tab.
- Did not add Settings, appearance controls, account/profile management, global preferences, device management, generic HealthKit dashboards, workout routines, social features, or duplicate Fitness/Mindfulness/Lab/Cycle/Oura/Watch surfaces.
- Replaced the Food placeholder screen with a full Pulsar Nutrition experience while preserving the existing root tab bar and app navigation.
- Added `PulsarNutritionModels` for local-first foods, meal entries, meal moments, hydration entries, body check-ins, target snapshots, meal templates, recipes, weekly points, eating rhythm, and insights.
- Added `PulsarNutritionProviding` plus a local file-backed provider so mock data can be replaced later by HealthKit, Oura, Fitness, and Apple Watch context without rewriting the SwiftUI layer.
- Seeded mock nutrition context for today and the prior week: meals, hydration, private foods, reusable templates, a recipe, weekly body context, and a recovery-aware target snapshot.
- Implemented `Nutrition Today` with a nourishment halo, fuel/protein/fiber/hydration signals, recovery-aware copy, and quick actions.
- Implemented `Daily Fuel Timeline` using meal moments: Morning, Midday, Evening, Snack, and Recovery.
- Added entry actions for edit, delete, duplicate, move, and repeat through context menus and edit sheets.
- Implemented `Fuel Capture` as a Liquid Glass sheet with mock search, private foods, quick estimate, manual entry, serving editor, nutrient impact preview, and confirmation.
- Implemented local-first `Private Foods`, recently reusable foods through saved/manual/recipe flows, `Meal Templates`, and `Recipe Studio`.
- Implemented hydration quick-add chips, hydration timeline, and daily hydration progress ring.
- Implemented nutrition-contextual body check-ins with weekly-first copy and no profile/settings duplication.
- Implemented recovery-aware target ranges for fuel, protein, fiber, and hydration using mock Pulsar recovery/activity context.
- Implemented `Weekly Nutrition Rewind` with consistency bars and protein/hydration/fiber trend language.
- Implemented `Nutrition Intelligence` cards for coach brief, recovery notes, hydration rhythm, timing, and weekly trends.
- Implemented optional eating rhythm visualization with non-diet-culture language and a local show/hide toggle.
- Added `NutritionStoreTests` covering food entry mutation, movement, duplication, deletion, hydration, meal templates, recipes, private foods, and file persistence.

## Phase 1 Validation

- Xcode build passed for the Pulsar project.
- Xcode full active test run passed: 245 tests, 245 passed, 0 failed.
- New Nutrition tests passed:
  - `NutritionStoreTests/testStoreLogsMovesDuplicatesAndDeletesFoodEntries()`
  - `NutritionStoreTests/testHydrationTemplatesAndRecipesUpdateLocalNutritionState()`
  - `NutritionStoreTests/testFileStorePersistsNutritionState()`
- Rendered the `FoodView` SwiftUI preview successfully and verified the top-level Nutrition Today and recovery-aware target surfaces render with the intended hierarchy.
- After tightening first-run mock seeding, reran the Pulsar project build successfully and reran all three Nutrition store tests successfully.
