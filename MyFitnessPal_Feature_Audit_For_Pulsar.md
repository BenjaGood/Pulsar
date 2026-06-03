# MyFitnessPal Feature Audit For Pulsar

Date: 2026-05-23  
Scope: Live audit through iPhone Mirroring on an existing signed-in MyFitnessPal account. Personal values, account identifiers, email addresses, dates of birth, and body metrics were intentionally not recorded.  
Constraint: iPhone Mirroring cannot expose the iPhone camera to the Mac, so camera-dependent barcode and meal-scan capture states were observed up to the scanner/onboarding/manual-entry surfaces, not with a real scan.  
Design constraint: This document studies functional patterns and user flows only. Pulsar should not copy MyFitnessPal branding, wording, icons, layouts, imagery, or proprietary visual design.

## Audit Summary

MyFitnessPal is organized around a utilitarian logging loop: dashboard summary, diary, quick-add launcher, progress charts, and a large More menu. Its strongest functional patterns are fast repeat food logging, a large searchable food database, many manual fallbacks, macro/nutrient breakdowns, reminders, and integrations. Its weakest qualities are visual density, fragmented navigation, aging webview surfaces, many tiny disclosure rows, inconsistent modal behavior, and an emotional tone that feels transactional rather than health-coaching oriented.

For Pulsar, the opportunity is to build a calmer nutrition system that feels native to the existing health platform: a Liquid Glass Daily Nutrition surface, fast original food capture flows, HealthKit/Oura/Apple Watch-aware recovery context, intelligent but restrained insights, elegant goal setting, and gentle coaching. Pulsar should prioritize fewer, higher-quality surfaces instead of reproducing every MyFitnessPal page one-for-one.

## Features Found

1. Home dashboard and calorie summary
2. Global quick-add launcher
3. Food diary and meal sections
4. Diary editing and item management
5. Food search, history, suggestions, and verified database results
6. Food detail logging with servings, meal, time, nutrition facts, and daily-goal percentages
7. Meal selector for breakfast, lunch, dinner, and snacks
8. Barcode scanner and manual barcode entry
9. Voice food logging
10. Meal photo scan onboarding
11. Quick Add calories/macros
12. My Foods and manual food creation
13. My Meals and meal creation
14. Recipe discovery and recipe detail pages
15. Meals, Recipes & Foods library
16. Nutrition dashboards: calories, nutrients, macros
17. Goals: weight, calories, macros, meal goals, nutrient goals, fitness goals
18. Weekly digest and food category insights
19. Progress charts and measurement selector
20. Weight logging and progress photo entry
21. Water logging
22. Exercise logging: cardio, strength, manual exercises, workout routines
23. Workout routine discovery and routine detail
24. Steps source settings and step goal
25. Apps & Devices integrations, including Apple Health
26. Sleep integration prompt
27. Intermittent fasting setup
28. Reminders and push notification settings
29. Streaks and food logging prompts
30. Premium plan and subscription status
31. Profile and personal settings
32. App appearance, diary settings, privacy/sharing, weekly settings
33. Learn/articles webview
34. Community/forums webview
35. Friends and messages
36. Help, privacy, support, account deletion, service status
37. Email verification gate for exports/reporting

## Feature Audit

### 1. Home Dashboard

1. Feature name: Home dashboard and daily calorie summary
2. Where it lives: Bottom tab `Dashboard`; first screen after launch.
3. User goal: Understand today's calorie budget, food logged, exercise adjustment, steps, weight, and next habit prompt.
4. Flow: Open app -> view calorie ring -> inspect remaining calories -> review steps/exercise/weight cards -> use plus affordances or the floating add button.
5. Data entered: None directly unless opening add flows.
6. Data calculated/displayed: Daily calorie goal, food calories, exercise calories, remaining calories, steps, step goal progress, weight, exercise time/calories, habit prompt.
7. UI patterns: Dashboard cards, circular calorie ring, compact metric cards, floating action button, horizontal/vertical card layout, badges, dark theme.
8. States: Empty cards with zeroes; filled cards with values; loading not prominent; error states mostly indirect through integration prompts; completed state through logged values.
9. Notifications/reminders: Links to streak and habit prompts; reminders configured elsewhere.
10. Useful because: Gives an immediate summary and one obvious add button.
11. Outdated/annoying/improvable: Dense information, calorie-centric framing, small tap targets, cluttered cards, weak emotional context.
12. Pulsar version: A calm Liquid Glass `Nutrition Today` surface with a soft energy balance orb, meal progress rail, hydration/recovery chips, and HealthKit-aware context. Use subtle parallax and native transitions; frame nutrition as nourishment and recovery, not only calorie arithmetic.

### 2. Global Quick-Add Launcher

1. Feature name: Quick-add launcher
2. Where it lives: Floating blue plus button from main tabs.
3. User goal: Quickly start a logging action.
4. Flow: Tap plus -> choose Log Food, Barcode Scan, Voice Log, Meal Scan, Water, Weight, or Exercise.
5. Data entered: None in the launcher.
6. Data calculated/displayed: Available entry types.
7. UI patterns: Bottom sheet grid with icon tiles and rows.
8. States: Closed; open; tutorial tooltip for first use.
9. Notifications/reminders: First-use educational prompt.
10. Useful because: Centralizes common actions.
11. Outdated/annoying/improvable: Mixed hierarchy; too many actions with similar weight; tutorial card occludes content.
12. Pulsar version: A Liquid Glass radial or compact command sheet with prioritized actions based on time of day and recent behavior: Breakfast, Hydrate, Scan Food, Voice Note, Log Weight. Keep icons native, motion soft, and actions context-aware.

### 3. Food Diary

1. Feature name: Food diary
2. Where it lives: Bottom tab `Diary`.
3. User goal: See and edit all daily nutrition entries by meal.
4. Flow: Open Diary -> view calorie remaining equation -> browse meal sections -> tap Add Food for a meal -> inspect meal entries -> edit diary if needed.
5. Data entered: Food entries, meal assignment, water, exercise, notes through linked flows.
6. Data calculated/displayed: Goal + food - exercise = remaining; meal totals; item calories; exercise adjustments; water section; fasting promo.
7. UI patterns: Equation header, meal sections, inline add links, ellipsis menus, promotional card, sticky tab bar.
8. States: Empty meal sections; filled meal sections; edit mode; promo state; tutorial tooltip.
9. Notifications/reminders: Meal reminders and streak prompts support the diary.
10. Useful because: The day is structured around familiar meal buckets.
11. Outdated/annoying/improvable: Promo interrupts the core diary; edit behavior is hidden; nutrition context is spread across other screens.
12. Pulsar version: A `Daily Fuel` timeline with glass meal capsules, unobtrusive nutrient rings, hydration lane, and optional reflection note. Use a gentle day timeline instead of a ledger.

### 4. Diary Editing

1. Feature name: Diary edit mode
2. Where it lives: Diary top-left `Edit`.
3. User goal: Copy, move, delete, or reorganize diary items.
4. Flow: Tap Edit -> select item(s) or sections -> use batch actions/reorder handles -> exit edit mode.
5. Data entered: Selection state; possible move/copy/delete targets.
6. Data calculated/displayed: Selected items, meal groups, item calories.
7. UI patterns: Check circles, select all, item rows, reorder handles.
8. States: No selection; selected; edit mode; disabled actions when nothing selected.
9. Notifications/reminders: None.
10. Useful because: Batch management matters for repeated meals.
11. Outdated/annoying/improvable: Hidden affordances and utilitarian controls.
12. Pulsar version: Native swipe actions for item-level work, contextual menus for move/copy, and a `Repeat Yesterday` glass suggestion. Keep bulk edit available but secondary.

### 5. Food Search And Suggestions

1. Feature name: Food search, history, suggestions, saved tabs
2. Where it lives: Add Food flow.
3. User goal: Find a food quickly and log it.
4. Flow: Choose meal -> search field -> see suggested searches -> submit query -> choose best match or database result -> inspect details or tap plus to log.
5. Data entered: Search query; selected food; optional meal/date/time.
6. Data calculated/displayed: Food calories, serving description, verified/check indicators, history, suggestions, filters, recent sort.
7. UI patterns: Search bar, segmented tabs, list rows, quick plus, verified badges.
8. States: Empty search/history; suggested searches; results; no-results possible; loading implicit; filled history.
9. Notifications/reminders: None directly.
10. Useful because: Search is fast and familiar.
11. Outdated/annoying/improvable: Database quality can feel noisy; rows are cramped; plus logging can be too easy to mis-tap.
12. Pulsar version: Search with trusted sources, recents, favorites, and confidence labels. Use preview sheets before logging, large touch targets, and transparent nutrient provenance.

### 6. Food Detail Logging

1. Feature name: Add Food detail
2. Where it lives: Selecting a food result.
3. User goal: Confirm serving, quantity, meal, and time before logging.
4. Flow: Select food -> edit serving size -> enter number of servings -> choose time and meal -> optionally add multiple days -> review macro ring and nutrition facts -> log.
5. Data entered: Serving size, number of servings, time, meal, date(s).
6. Data calculated/displayed: Calories, carbs, fat, protein, percent of daily goals, detailed nutrition facts.
7. UI patterns: Form rows, date chips, macro ring, daily goal bars, disclosure for nutrition facts, top-right log action.
8. States: Valid entry; invalid/missing serving; expanded/collapsed nutrition; report-food link.
9. Notifications/reminders: None.
10. Useful because: It prevents blind logging and exposes macro impact.
11. Outdated/annoying/improvable: Form-heavy; top-right save can feel detached; daily goal percentages are visually cramped.
12. Pulsar version: A glass bottom sheet with serving steppers, portion presets, haptic macro preview, and an animated impact preview on today's nutrition ring.

### 7. Meal Selector

1. Feature name: Meal selector
2. Where it lives: Add Food top title and food detail meal field.
3. User goal: Assign food to the right meal.
4. Flow: Tap current meal -> choose Breakfast, Lunch, Dinner, or Snacks -> continue logging.
5. Data entered: Meal category.
6. Data calculated/displayed: Updated meal target/placement.
7. UI patterns: Popover/list selector.
8. States: Selected meal; unselected/default; toast after logging.
9. Notifications/reminders: Meal reminders map to these categories.
10. Useful because: Simple canonical structure.
11. Outdated/annoying/improvable: Fixed meal names unless buried in settings; selection can be easy to confuse with logging state.
12. Pulsar version: Customizable meal moments with time-aware defaults: Morning, Midday, Evening, Recovery, Snack. Display as elegant segmented chips.

### 8. Barcode Scan

1. Feature name: Barcode scanner and manual barcode entry
2. Where it lives: Quick-add launcher and Add Food toolbar.
3. User goal: Identify packaged foods quickly.
4. Flow: Tap Barcode Scan -> camera scanner opens -> aim at barcode; or tap manual barcode field -> type barcode -> confirm.
5. Data entered: Camera scan or barcode number.
6. Data calculated/displayed: Product lookup, nutrition facts, serving options after a successful scan.
7. UI patterns: Fullscreen scanner, framing corners, bottom manual entry field, top back/check controls.
8. States: Permission prompt; scanning; camera unavailable in iPhone Mirroring; manual entry; lookup/no match; result detail.
9. Notifications/reminders: None.
10. Useful because: Best path for packaged-food speed.
11. Outdated/annoying/improvable: Camera permission/camera unavailable failure is not graceful; manual entry is cramped.
12. Pulsar version: Native scanner with a calm glass frame, clear permission education, manual fallback, and post-scan confidence state. Save scanned foods privately with source metadata.

### 9. Voice Food Logging

1. Feature name: Voice Log
2. Where it lives: Add Food toolbar and quick-add launcher.
3. User goal: Log food by speaking natural language.
4. Flow: Tap Voice Log -> bottom sheet shows example phrase -> tap Start Voice Logging -> speak meal -> app parses foods/servings.
5. Data entered: Spoken meal description.
6. Data calculated/displayed: Parsed items, inferred quantities, candidate foods, nutrition totals.
7. UI patterns: Bottom sheet, example sentence with highlighted quantities/foods, primary CTA.
8. States: Intro; microphone permission; recording; parsing; confirmation; error/no match.
9. Notifications/reminders: None.
10. Useful because: Reduces typing friction.
11. Outdated/annoying/improvable: Example is helpful but visually basic; privacy expectations are unclear.
12. Pulsar version: On-device-first voice capture where possible, transcript chips, calm waveform, and an editable food confirmation stack. Make privacy and confidence explicit.

### 10. Meal Scan

1. Feature name: Meal Scan
2. Where it lives: Add Food toolbar and quick-add launcher.
3. User goal: Capture a meal photo and identify multiple foods.
4. Flow: Tap Meal Scan -> onboarding carousel explains full-meal capture -> scan meal -> app detects foods -> user selects multiple foods -> user searches missing items -> review and log.
5. Data entered: Meal photo, selected detected foods, manually added missing foods.
6. Data calculated/displayed: Detected food candidates, servings, nutrition estimates.
7. UI patterns: Multi-step onboarding carousel, image preview, selectable food list, review CTA.
8. States: Onboarding; camera permission; scanning; detected results; missing-item search; review; error/no detection.
9. Notifications/reminders: None.
10. Useful because: Handles mixed meals better than barcode/search.
11. Outdated/annoying/improvable: Onboarding feels lengthy; scanning is camera-dependent; confidence/serving uncertainty needs more clarity.
12. Pulsar version: A premium `Plate Capture` flow with glass detection overlays, confidence bands, editable portion cards, and a "good enough estimate" philosophy.

### 11. Quick Add Calories/Macros

1. Feature name: Quick Add
2. Where it lives: Add Food toolbar `Quick add`.
3. User goal: Enter calories/macros without selecting a food database item.
4. Flow: Open Quick Add -> select meal -> enter calories -> optional fat/carbs/protein -> choose time -> save.
5. Data entered: Calories, fat, carbs, protein, meal, time.
6. Data calculated/displayed: Daily totals and macro totals update after saving.
7. UI patterns: Minimal form rows, disabled save until required value.
8. States: Empty; valid; optional macro-filled; completed after save.
9. Notifications/reminders: None.
10. Useful because: Fast fallback when precision is not needed.
11. Outdated/annoying/improvable: Bare utility screen; no confidence/note context.
12. Pulsar version: `Estimate Intake` with sliders/chips, confidence label, optional note, and elegant macro impact preview.

### 12. My Foods And Manual Food Creation

1. Feature name: My Foods and Create Food
2. Where it lives: Add Food tabs and More -> Meals, Recipes & Foods -> Foods.
3. User goal: Save personal food entries for reuse.
4. Flow: Open My Foods -> empty state -> Create Food -> enter brand, description, serving size, servings per container -> continue to nutrition details -> save.
5. Data entered: Food identity, serving metadata, nutrition facts.
6. Data calculated/displayed: Personal database entry and nutrition totals.
7. UI patterns: Segmented tab, empty state illustration, form rows, top-right progression action.
8. States: Empty; filled library; create form; invalid required fields; saved.
9. Notifications/reminders: None.
10. Useful because: Personal foods reduce repeated manual entry.
11. Outdated/annoying/improvable: Manual entry is tedious and visually plain.
12. Pulsar version: `Private Foods` with scan/import/manual modes, natural-language nutrition parsing, source labels, and reusable serving presets.

### 13. My Meals And Meal Creation

1. Feature name: My Meals and Create Meal
2. Where it lives: Add Food tabs and More -> Meals, Recipes & Foods -> Meals.
3. User goal: Save common combinations of foods.
4. Flow: Open My Meals -> Create Meal -> add photo/name -> choose sharing privacy -> add meal items -> optional directions -> save.
5. Data entered: Meal name, photo, privacy, ingredients/items, directions.
6. Data calculated/displayed: Total calories/macros, nutrition facts, item list.
7. UI patterns: Hero header, add-photo button, macro summary, sections, sticky Add Food button.
8. States: Empty; draft; invalid missing name/items; saved; public/private.
9. Notifications/reminders: None.
10. Useful because: Great for repeated breakfasts/lunches.
11. Outdated/annoying/improvable: Share setting feels exposed by default; form is heavy.
12. Pulsar version: `Meal Templates` as private-by-default glass cards with one-tap "log this again", smart serving scaling, and optional photo memory.

### 14. Recipe Discovery And Detail

1. Feature name: Recipe discovery
2. Where it lives: More -> Recipe Discovery.
3. User goal: Browse recipes and log them to diary.
4. Flow: Open Recipes -> browse category carousels -> open recipe -> review tags, nutrition per serving, ingredients, expanded nutrition -> log to diary.
5. Data entered: Recipe selection; optional diary logging.
6. Data calculated/displayed: Calories/macros per serving, tags, ingredients, daily goal percentages.
7. UI patterns: Image cards, horizontal carousels, saved bookmark, hero image detail, sticky log button.
8. States: Loading; browse; detail; saved; logged; blocked if network fails.
9. Notifications/reminders: None.
10. Useful because: Moves from inspiration to logging.
11. Outdated/annoying/improvable: Recipe discovery feels like a separate content product; images dominate but personalization is shallow.
12. Pulsar version: `Nourish Ideas` powered by goals/recovery/preferences, with elegant recipe cards and clear nutrient/recovery fit. Keep content subtle, not feed-like.

### 15. Meals, Recipes & Foods Library

1. Feature name: Meals, Recipes & Foods library
2. Where it lives: More -> My Meals, Recipes & Foods.
3. User goal: Manage personal reusable nutrition objects.
4. Flow: Open library -> switch Recipes/Meals/Foods -> search -> create selected type -> sort display options.
5. Data entered: Search, created objects, sort order.
6. Data calculated/displayed: Saved objects, empty guidance, sort state.
7. UI patterns: Search bar, segmented tabs, empty states, bottom create button, display options sheet.
8. States: Empty; filled; search results; create form; sort selected.
9. Notifications/reminders: None.
10. Useful because: Central source for reusable items.
11. Outdated/annoying/improvable: Library is buried and visually sparse.
12. Pulsar version: A first-class `Nutrition Library` with private cards, smart folders, recent templates, and clean source/history metadata.

### 16. Nutrition Dashboards

1. Feature name: Nutrition dashboards
2. Where it lives: More -> Nutrition.
3. User goal: Understand daily calories, nutrient totals, and macro split.
4. Flow: Open Nutrition -> switch Calories/Nutrients/Macros -> change day/view -> inspect charts/tables -> view highest contributing foods -> export if eligible.
5. Data entered: Date/view selection.
6. Data calculated/displayed: Pie charts, totals, goals, remaining nutrients, highest-food contributors.
7. UI patterns: Segmented tabs, date navigation, pie charts, tables, export action.
8. States: Empty/zero; filled; export blocked by email verification; different views.
9. Notifications/reminders: None.
10. Useful because: Shows why totals are high/low.
11. Outdated/annoying/improvable: Dense tables; chart styling feels basic; export gate is abrupt.
12. Pulsar version: Calm nutrient insight cards: "Protein steady", "Fiber low", "Sodium elevated", with expandable detail. Use simple rings/trendlets, not table-first design.

### 17. Goals

1. Feature name: Goals
2. Where it lives: More -> Goals and Profile -> Goals.
3. User goal: Configure weight, calorie, macro, nutrient, and fitness targets.
4. Flow: Open Goals -> edit starting/current/goal weight, weekly goal, activity level -> open calorie/macro goals -> open meal goals -> additional nutrients -> fitness goals.
5. Data entered: Weight targets, weekly rate, activity level, calorie/macro values, meal goals, nutrients, workouts/week, minutes/workout, exercise calorie behavior.
6. Data calculated/displayed: Recommended calories/macros, grams/percent, nutrient goals, fitness target values.
7. UI patterns: Settings list, nested detail screens, toggles, pickers, segmented calories/% control.
8. States: Defaults; customized; premium meal goals; invalid values; saved values.
9. Notifications/reminders: Goals influence reminders and dashboard totals.
10. Useful because: Centralizes personalization.
11. Outdated/annoying/improvable: Deep nesting; no coaching rationale except small "how recommendations" links.
12. Pulsar version: Guided `Nutrition Targets` setup with recovery-aware recommendations, animated macro balance, and clear "why this target" explanations.

### 18. Weekly Digest

1. Feature name: Weekly Digest / Food Insights
2. Where it lives: More -> My Weekly Report.
3. User goal: Review weekly logged-food patterns.
4. Flow: Open Weekly Digest -> select/view date range -> review food-category counts such as vegetables, fruit, proteins, sweets, alcohol.
5. Data entered: None directly.
6. Data calculated/displayed: Weekly category counts and educational labels.
7. UI patterns: Webview-like report, white article layout, illustrated header, vertical insight cards.
8. States: Loading; report; empty week; category counts.
9. Notifications/reminders: Weekly reminder can exist through reminders.
10. Useful because: Converts logs into pattern feedback.
11. Outdated/annoying/improvable: Webview styling breaks app consistency; insights are count-based and shallow.
12. Pulsar version: `Weekly Nutrition Rewind` using Pulsar's existing Daily Rewind language: cinematic summary, nutrient consistency, recovery correlations, and 2-3 gentle next-week suggestions.

### 19. Progress Charts

1. Feature name: Progress
2. Where it lives: Bottom tab Progress and More -> Progress.
3. User goal: Track measurements over time.
4. Flow: Open Progress -> choose measurement -> choose date range -> view chart and entries -> use share/export if eligible.
5. Data entered: Measurement type/date range.
6. Data calculated/displayed: Average, best, total, chart bars/line, entries list.
7. UI patterns: Header selectors, chart, entries list, bottom picker sheets.
8. States: Empty; filled; picker; export/verify email gate.
9. Notifications/reminders: Weight reminders can create entries.
10. Useful because: Shows trend and historical entries.
11. Outdated/annoying/improvable: Chart is sparse; measurement picker is hidden; limited narrative.
12. Pulsar version: Integrated body and behavior trends with Liquid Glass chart cards, monthly narrative, and correlations with sleep/workouts/recovery.

### 20. Weight Logging

1. Feature name: Add Weight
2. Where it lives: Dashboard weight card plus and quick-add launcher.
3. User goal: Record current weight and optional progress photo.
4. Flow: Tap weight plus -> Add Weight -> edit weight/date -> optional progress photo -> save.
5. Data entered: Weight, date, photo.
6. Data calculated/displayed: Weight change, progress chart, goal progress.
7. UI patterns: Minimal form, top-right save, optional photo row.
8. States: Prefilled current value; edited; saved; invalid value.
9. Notifications/reminders: Weekly weight reminder.
10. Useful because: Fast body metric tracking.
11. Outdated/annoying/improvable: Weight is isolated from recovery/body composition context.
12. Pulsar version: `Body Check-In` with weight, waist/body measurements, optional photo, confidence notes, and trend smoothing. Avoid overemphasizing daily fluctuations.

### 21. Water Logging

1. Feature name: Add Water
2. Where it lives: Quick-add launcher and diary if enabled.
3. User goal: Log hydration quickly.
4. Flow: Tap Water -> enter amount or quick-add +250/+500/+1000 ml -> change unit if needed -> save.
5. Data entered: Water amount, unit.
6. Data calculated/displayed: Hydration total and diary water section.
7. UI patterns: Centered bottle illustration, numeric field, quick-add buttons, unit link.
8. States: Empty; amount entered; saved; invalid amount.
9. Notifications/reminders: No direct water reminder observed, but could be configured conceptually.
10. Useful because: Quick common quantities.
11. Outdated/annoying/improvable: Visual is generic; hydration has no context.
12. Pulsar version: Hydration ring with glass droplets, Apple Watch quick add, sweat/workout/weather-aware suggestions, and low-friction haptics.

### 22. Exercise Logging

1. Feature name: Exercise logging
2. Where it lives: Dashboard exercise card plus, quick-add launcher, Diary exercise section.
3. User goal: Log activity that adjusts calorie budget.
4. Flow: Tap Exercise plus -> choose Cardio, Strength, or Workout Routines -> search or browse exercises -> select item -> enter minutes/calories/start time or strength sets/reps/weight -> save.
5. Data entered: Exercise type, duration, calories, start time, sets, reps, weight.
6. Data calculated/displayed: Exercise calories, diary adjustment, history, personal exercises.
7. UI patterns: Action sheet, searchable exercise database, tabs, empty history, form entry, multi-add.
8. States: Empty history; all exercises list; add entry; custom exercise; multi-add; saved.
9. Notifications/reminders: Push options for friends' workouts; dashboard shows exercise.
10. Useful because: Connects activity to food budget.
11. Outdated/annoying/improvable: Manual exercise calories are imprecise; health integration should dominate.
12. Pulsar version: HealthKit-first exercise integration. Manual logging should be secondary, with Pulsar workouts automatically contributing to nutrition/recovery insights without crude calorie compensation.

### 23. Workout Routines

1. Feature name: Workout routines
2. Where it lives: More -> Workout Routines and exercise action sheet.
3. User goal: Browse guided routines and log/start them.
4. Flow: Open Explore -> browse categories -> open routine -> watch preview/read overview -> review equipment/exercises -> start or log workout.
5. Data entered: Routine selection and possible workout log.
6. Data calculated/displayed: Duration, bodyweight/equipment, overview, exercise list.
7. UI patterns: Explore/My Routines tabs, video thumbnails, detail page, sticky Start/Log buttons.
8. States: Loading; explore; detail; my routines empty; started/logged.
9. Notifications/reminders: None observed.
10. Useful because: Adds fitness guidance.
11. Outdated/annoying/improvable: Feels bolted onto a nutrition app; not deeply tied to recovery.
12. Pulsar version: Pulsar already has Fitness; nutrition should consume workout data rather than embed generic workout content.

### 24. Steps

1. Feature name: Steps source and goal
2. Where it lives: More -> Steps and dashboard steps card.
3. User goal: Choose step source and daily target.
4. Flow: Open Steps -> choose iPhone, Apple Watch, add device, or don't track -> edit daily step goal.
5. Data entered: Source preference, step goal.
6. Data calculated/displayed: Steps, step goal progress, calorie adjustment.
7. UI patterns: Selection list, checkmark, goal row.
8. States: Device selected; no tracking; add device; goal configured.
9. Notifications/reminders: Push notification option for reaching step goal.
10. Useful because: Clarifies data source.
11. Outdated/annoying/improvable: Source selection is buried; Apple Health integration page duplicates some concepts.
12. Pulsar version: Use Pulsar's existing source-priority model and HealthKit trust layer; show source provenance inline where it matters.

### 25. Apps & Devices

1. Feature name: Apps & Devices integrations
2. Where it lives: More -> Apps & Devices.
3. User goal: Connect external health, workout, and device apps.
4. Flow: Open Apps & Devices -> browse featured integrations -> search/list all apps -> open integration -> connect/settings.
5. Data entered: Integration authorization.
6. Data calculated/displayed: Connected count, app descriptions, settings status.
7. UI patterns: Featured horizontal app icons, segmented All/Connected, searchable list.
8. States: Loading; all; connected; integration detail; permission settings.
9. Notifications/reminders: Integration data powers dashboard/diary.
10. Useful because: Enables automatic activity and health data.
11. Outdated/annoying/improvable: Integration browsing feels like an app directory; Apple Health settings handoff is terse.
12. Pulsar version: Native `Data Sources` screen that explains read/write permissions, confidence, freshness, and ownership across HealthKit, Oura, Watch, and manual logs.

### 26. Apple Health Integration

1. Feature name: Health App integration
2. Where it lives: Apps & Devices -> Health App.
3. User goal: Manage Apple Health data sharing.
4. Flow: Open Health App integration -> review explanation -> tap Settings to manage permissions.
5. Data entered: Health permission choices in system settings.
6. Data calculated/displayed: Health data imported/exported depending on permissions.
7. UI patterns: Integration detail page, app icon, settings button, illustrative screenshot.
8. States: Connected/settings available; permissions missing; system handoff.
9. Notifications/reminders: None.
10. Useful because: Apple Health can automate steps, workouts, sleep, body metrics.
11. Outdated/annoying/improvable: Does not clearly show actual active permissions or freshness.
12. Pulsar version: A living HealthKit permissions dashboard with per-signal freshness, source priority, and repair actions.

### 27. Sleep

1. Feature name: Sleep integration prompt
2. Where it lives: More -> Sleep.
3. User goal: Understand how logged food relates to sleep.
4. Flow: Open Sleep -> see explanatory screen -> tap Update Permissions to connect Apple Health sleep.
5. Data entered: HealthKit permissions.
6. Data calculated/displayed: Sleep/food trend correlations once connected.
7. UI patterns: Illustration, explanatory copy, primary permission CTA.
8. States: Not connected; permission flow; connected trends.
9. Notifications/reminders: None observed.
10. Useful because: Nutrition timing and sleep are meaningfully related.
11. Outdated/annoying/improvable: Permission prompt appears before showing much value.
12. Pulsar version: Pulsar can do this better with existing sleep/recovery: "Late heavy meals and sleep quality" insights, meal timing trendlets, and gentle experiments.

### 28. Intermittent Fasting

1. Feature name: Intermittent fasting
2. Where it lives: More -> Intermittent Fasting and diary promo.
3. User goal: Set and track eating/fasting windows.
4. Flow: Open feature -> read intro -> Get Started -> choose fasting goal 12:12, 14:10, or 16:8 -> continue setup.
5. Data entered: Fasting pattern, later likely schedule/start time.
6. Data calculated/displayed: Fasting/eating windows, tracker state.
7. UI patterns: Promotional intro, onboarding setup, selectable cards, abandon confirmation.
8. States: Not set up; setup; selected pattern; active tracker; discard setup.
9. Notifications/reminders: Likely eating/fasting reminders, not fully configured in audit.
10. Useful because: Time-window tracking can help meal consistency.
11. Outdated/annoying/improvable: Promo appears in diary; setup is generic.
12. Pulsar version: Optional `Eating Window` rhythm tied to sleep, workouts, and recovery. Avoid diet-culture framing; make it a schedule awareness tool.

### 29. Reminders

1. Feature name: Reminders
2. Where it lives: More -> Reminders and Settings -> Push Notifications.
3. User goal: Receive meal/weight reminders and behavioral prompts.
4. Flow: Open Reminders -> view meal reminders and weekly weight reminder -> toggle on/off -> open reminder -> edit meal/frequency/day/time or delete -> add new reminder.
5. Data entered: Reminder type, meal, frequency, day, time, enabled state.
6. Data calculated/displayed: Schedule list and active toggles.
7. UI patterns: Settings list, toggles, edit form, destructive delete button.
8. States: Enabled/disabled; add; edit; delete confirmation likely; notification permission dependency.
9. Notifications/reminders: Breakfast/lunch/dinner reminders, weekly weigh-in, push notification categories.
10. Useful because: Logging consistency depends on prompts.
11. Outdated/annoying/improvable: Reminders are blunt time alarms; no context awareness.
12. Pulsar version: Intelligent check-ins based on routine, sleep, workouts, and missed patterns. Use quiet notification language and let users set tone/intensity.

### 30. Streaks

1. Feature name: Food logging streak
2. Where it lives: Dashboard/Diary lightning icon and More header.
3. User goal: Build consistency by logging food daily.
4. Flow: Tap streak icon -> see streak prompt -> log food to continue streak.
5. Data entered: Food logs.
6. Data calculated/displayed: Current streak count and streak prompt.
7. UI patterns: Badge/icon, popover, CTA.
8. States: No streak; active streak; broken streak; prompt.
9. Notifications/reminders: Meal reminders and streak push options.
10. Useful because: Reinforces habit.
11. Outdated/annoying/improvable: Can feel gamified or guilt-inducing.
12. Pulsar version: Use "consistency" rather than streak pressure. Show calm weekly rhythm rings and compassionate recovery after missed days.

### 31. Premium And Subscription

1. Feature name: Premium plan and subscription status
2. Where it lives: More -> My Premium, Settings -> Subscription Status, crown-tagged features.
3. User goal: Understand premium benefits and subscription state.
4. Flow: Open My Premium -> see benefits and current plan -> open Subscription Status -> view active term and manage subscription.
5. Data entered: None unless managing subscription externally.
6. Data calculated/displayed: Subscription status, expiration/term, premium benefit list.
7. UI patterns: Yellow premium card, benefit list, crown icons, manage link.
8. States: Active plan; paywall for non-subscribers likely; premium feature labels.
9. Notifications/reminders: None.
10. Useful because: Clarifies unlocked capabilities.
11. Outdated/annoying/improvable: Premium color/benefit list feels commercial.
12. Pulsar version: Premium nutrition should feel like a deeper intelligence layer, not locked toggles. Use graceful locked previews and explain value in health outcomes.

### 32. Profile And Personal Settings

1. Feature name: Profile
2. Where it lives: More header and More -> My Profile -> Edit Profile.
3. User goal: Manage identity, units, body details, goals, and account info.
4. Flow: Open profile -> view avatar/account summary -> Edit Profile -> edit username/photo/height/sex/birth date/location/zip/time zone/email/units/goals.
5. Data entered: Personal identifiers and health/body attributes.
6. Data calculated/displayed: Weight lost/progress, unit preferences, linked goals.
7. UI patterns: Profile header, stats row, settings form.
8. States: Complete profile; missing fields; edit form.
9. Notifications/reminders: Time zone/units affect reminders/logging.
10. Useful because: Personalization affects calculations.
11. Outdated/annoying/improvable: Sensitive fields are plain rows; limited privacy reassurance.
12. Pulsar version: A health profile vault with progressive disclosure, privacy language, and clear calculation impact for each field.

### 33. App Settings

1. Feature name: Settings
2. Where it lives: More -> Settings.
3. User goal: Configure app behavior.
4. Flow: Open Settings -> choose Profile, App Appearance, Diary Settings, Sharing & Privacy, My Exercises, Weekly Nutrition Settings, Push Notifications, Subscription Status, or Logout.
5. Data entered: Theme, diary preferences, sharing/privacy, notification categories, weekly start day, custom exercises.
6. Data calculated/displayed: Setting states and defaults.
7. UI patterns: Nested settings list, toggles, picker rows.
8. States: Default/custom; enabled/disabled; empty custom exercise list.
9. Notifications/reminders: Push notification settings, reminder settings.
10. Useful because: Provides control.
11. Outdated/annoying/improvable: Deep, fragmented settings with little explanation.
12. Pulsar version: Settings grouped by `Nutrition`, `Data`, `Privacy`, and `Coaching`, with inline previews and native iOS forms.

### 34. Diary Settings

1. Feature name: Diary Settings
2. Where it lives: Settings -> Diary Settings.
3. User goal: Customize diary behavior and nutrient display.
4. Flow: Open Diary Settings -> toggle macro-by-meal, all meal tabs, multi-add default, food insights, water in diary, timestamps -> choose default search tab, diary sharing, meal names, nutrient dashboard.
5. Data entered: Toggle and preference choices.
6. Data calculated/displayed: Diary layout and logging defaults.
7. UI patterns: Toggle list, nested rows.
8. States: On/off; selected default; customized meal names/nutrients.
9. Notifications/reminders: None directly.
10. Useful because: Power users can tune logging.
11. Outdated/annoying/improvable: Many toggles expose implementation details.
12. Pulsar version: Offer fewer but smarter preferences: meal names, visible nutrients, water visibility, precision mode, and default logging method.

### 35. Learn

1. Feature name: Learn/articles
2. Where it lives: More -> Learn.
3. User goal: Read nutrition/health content.
4. Flow: Open Learn -> accept/manage cookies in webview -> search -> browse spotlight article and topic chips.
5. Data entered: Search query, cookie preferences.
6. Data calculated/displayed: Article cards, topic categories.
7. UI patterns: Embedded webview, cookie banner, search, topic chips, article cards.
8. States: Loading; cookie prompt; browse; search results.
9. Notifications/reminders: None.
10. Useful because: Education can support behavior change.
11. Outdated/annoying/improvable: Webview breaks native feel; cookie banner is distracting.
12. Pulsar version: Native micro-lessons tied to insights, not a generic article feed. Use compact cards and optional deep dives.

### 36. Community, Friends, Messages

1. Feature name: Community/social features
2. Where it lives: More -> Community, Friends, Messages.
3. User goal: Ask questions, get support, connect with friends, read messages.
4. Flow: Open Community -> browse forum categories/search/post; open Friends -> manage social connections; open Messages -> view inbox/sent.
5. Data entered: Posts, messages, friend requests.
6. Data calculated/displayed: Forum threads, message counts, badges.
7. UI patterns: Embedded forum webview, list tabs, message inbox, notification badge.
8. States: Loading; inbox; empty/filled; unread badge.
9. Notifications/reminders: Push settings for messages/friend requests/friend activity.
10. Useful because: Support can help adherence.
11. Outdated/annoying/improvable: Forums feel outside the app and can add clutter.
12. Pulsar version: Do not start with social/community. If needed later, use private coaching or small trusted circles, never noisy public forums.

### 37. Help, Privacy, Verification

1. Feature name: Help, privacy, support, verification gates
2. Where it lives: More -> Help, More -> Privacy, export/report actions.
3. User goal: Access support, legal/privacy settings, service status, account deletion, and verify email for exports.
4. Flow: Open Help -> FAQ/contact/support/delete/service status; open Privacy -> terms/privacy/data consents/personalization/email settings; attempt export -> verify email gate appears if needed.
5. Data entered: Support request, privacy preferences, verification actions.
6. Data calculated/displayed: Legal/support pages, verification status.
7. UI patterns: Settings list, webviews, full-page gate with CTA.
8. States: Normal; blocked by verification; support; destructive account deletion path.
9. Notifications/reminders: Email/push settings.
10. Useful because: Trust and support are required for health data products.
11. Outdated/annoying/improvable: Verification gate appears abruptly after export tap; privacy controls are fragmented.
12. Pulsar version: Clear account readiness checklist, privacy dashboard, and export prep messaging before blocking a requested report.

## Proposed Pulsar Nutrition System

Pulsar should implement an original nutrition system built around five primary experiences:

1. Nutrition Today: A calm daily overview showing nourishment, macros, hydration, meal timing, recovery context, and confidence.
2. Fast Logging: Search, scan, voice, quick estimate, reusable meals, and water/weight actions from one native command surface.
3. Nutrition Diary: A day timeline with meal moments, food entries, hydration, exercise context, and gentle completion state.
4. Insights And Goals: Recovery-aware targets, nutrient trend cards, weekly rewind, and correlations with sleep, workouts, stress, HRV, Oura, and Apple Watch.
5. Nutrition Library: Personal foods, meal templates, recipes, saved scans, and trusted source metadata.

Pulsar should avoid a calorie-only product. Calories can exist, but the primary language should include energy availability, protein consistency, fiber, hydration, recovery, sleep compatibility, and training support.

## Implementation Order

1. Data foundation: nutrition models, serving model, meal moments, diary entries, nutrient totals, hydration/weight entries, mock repository.
2. Nutrition Today shell: Liquid Glass daily dashboard using mock data and existing Pulsar visual language.
3. Diary timeline: meal sections, entries, daily totals, empty/filled states, edit/delete architecture.
4. Fast Add command sheet: food search placeholder, quick estimate, water, weight, exercise import placeholder.
5. Food detail and manual entry: serving controls, nutrient preview, save to mock/local store.
6. Nutrition targets: calories/macros/nutrients settings with HealthKit-aware recommendations placeholder.
7. Nutrition insights: daily cards and weekly rewind mock engine.
8. Library: saved foods, meal templates, recipes/ideas mock states.
9. Integrations: HealthKit nutrition/body/water where available, existing workout/steps/recovery context, Oura correlations.
10. Notifications: meal/water/weekly review reminders after product states are stable.
11. Premium layer: advanced insights, reports, coaching, export, and AI-assisted logging behind graceful previews.
12. QA and polish: previews, accessibility, animations, tab integration, persistence migration tests, and no regressions to Fitness/Mindfulness/Lab/Cycle/Oura/Watch.

## Risk Notes

- Food logging is sensitive health-adjacent behavior. Pulsar should make privacy, source, and confidence visible.
- Camera, microphone, and HealthKit permissions need explicit, native rationale screens.
- AI food recognition and voice parsing must always provide an editable confirmation step.
- Do not over-gamify nutrition; missed logs should not feel punitive.
- Avoid making nutrition feel detached from the rest of Pulsar. The best differentiator is correlation with recovery, sleep, stress, workouts, and Apple Watch data.
