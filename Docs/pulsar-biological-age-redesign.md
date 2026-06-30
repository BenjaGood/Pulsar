# Pulsar Biological Age Redesign

## Assumptions

- Pulsar already has reliable first-party scoring surfaces for sleep, recovery, strain, stress, nutrition, mindfulness, Oura import, HealthKit import, and Lab.
- The current Lab biological-age engine is useful as a provisional wellness feature, but its paradigm is a moderated weighted-pillar delta over chronological age. It does not yet model biological age as a latent functional state, does not make sleep structurally dominant, and treats Pace of Aging as a trend derivative rather than a separately modeled short-term signal.
- The redesign should introduce a new model family behind the existing Lab UX rather than directly mutating current `BiologicalAgeResult` semantics in one step.
- Pulsar should present this as a longitudinal wellness estimate, not as diagnosis, disease detection, treatment guidance, or a claim that the user's body is literally a different age.
- The first production version should be explainable, deterministic for the same model version and input, robust to missingness, and auditable by data source and feature window.
- Sleep stage values from wearables should be treated as probabilistic features. Duration, regularity, continuity, and nocturnal physiology must keep working when stage data is absent.

## Data Schemas

The production contract should separate raw ingest from derived feature input. The app can keep native Swift models, but the scoring service should expose versioned JSON contracts that map cleanly to Python dataclasses or Pydantic models.

### Ingestion Domains

| Domain | Minimum records | Required provenance |
| --- | --- | --- |
| Identity | pseudonymous user id, chronological age, declared sex if provided, timezone, country or region | profile source, consent state, schema version |
| Sleep | bedtime, wake time, time in bed, total sleep time, sleep midpoint, latency, WASO, awakenings, stages when available | device/source, sleep date key, timezone, stage confidence |
| Nocturnal physiology | HR min/mean, resting HR, HRV RMSSD or SDNN, respiratory rate, SpO2, skin temperature, PPG quality | window coverage, artifact rejection, aggregation method |
| Training | workout type, duration, HR zones, strain/load, steps, distance, active energy, strength sessions, VO2 max when available | HealthKit/Oura/app source, workout id, duplicate status |
| Nutrition | calories, protein, fiber, alcohol, caffeine timing, last meal timing, meal consistency | manual/logging source, confidence, time relative to sleep |
| Mindfulness/stress | minutes, session type, time of day, stress pre/post, breathwork, HRV biofeedback if available | app session id, completion status |
| PROMs | perceived sleep quality, energy, mood, soreness, stress, illness, travel/jet lag, naps | survey version, scale definition |
| Quality | wear time, coverage, PPG quality, staging confidence, missingness reason, source changes | ruleset version |

### Scoring Input

The inference input should be one user-day with rolling features, masks, source metadata, and optional personal baselines.

```json
{
  "schema_version": "bioage.input.v1",
  "user_id": "u_123",
  "date": "2026-06-20",
  "chronological_age": 36.4,
  "timezone": "America/Mexico_City",
  "source_mix": ["healthkit", "oura"],
  "sleep": {},
  "training": {},
  "nutrition": {},
  "mindfulness": {},
  "proms": {},
  "baselines": {},
  "missingness": {},
  "quality": {}
}
```

### Scoring Output

The output must always include uncertainty, quality flags, model version, and drivers.

```json
{
  "schema_version": "bioage.output.v1",
  "model_version": "pulsar-bioage-sleepfirst-1.0.0",
  "user_id": "u_123",
  "date": "2026-06-20",
  "biological_age_years": 34.8,
  "age_gap_years": -1.6,
  "pace_of_aging_x": 0.82,
  "sleep_age_years": 33.9,
  "confidence": {
    "level": "high",
    "score": 0.86,
    "p10": 33.7,
    "p50": 34.8,
    "p90": 36.2
  },
  "subscores": {
    "sleep_core": 0.82,
    "autonomic_recovery": 0.78,
    "sleep_architecture": 0.73,
    "sleep_continuity": 0.84,
    "circadian_regularity": 0.69,
    "sleep_resilience": 0.76,
    "training": 0.71,
    "nutrition": 0.64,
    "mindfulness": 0.68
  },
  "drivers": [],
  "quality_flags": [],
  "recommendations": []
}
```

## Feature Engineering

Features should be computed for 7, 28, 84, and 180 day windows. The 28 day window is the main product window. The 84 and 180 day windows stabilize biological age. The 7 day window powers Pace of Aging and explanations for recent change.

### Feature Inventory

| Domain | Core features |
| --- | --- |
| Sleep duration/timing | total sleep time mean/median, time in bed, sleep midpoint mean and SD, bedtime SD, wake time SD, social jetlag, nights valid, target-sleep adequacy |
| Sleep continuity | efficiency, WASO, awakenings, bout length, fragmentation index, transition count, continuity entropy, naps if tracked |
| Sleep architecture | REM %, deep/N3 %, core/N2 %, N3 first-third ratio, REM last-half ratio, REM latency, stage confidence, stage missing mask |
| Autonomic recovery | nocturnal HR min/mean, resting HR, HRV RMSSD/SDNN median, HRV coefficient of variation, respiratory rate, SpO2, skin temperature deviation, PPG quality |
| Sleep resilience | next-night HRV after high strain, WASO after late meals/alcohol/caffeine, sleep duration rebound after sleep debt, recovery slope after stress |
| Training | zone 2 minutes, zone 4/5 minutes, strength sessions, acute/chronic load ratio, steps, workout frequency, active minutes, VO2 max, high-strain streaks |
| Nutrition | protein, fiber, alcohol days, late meal days, caffeine after cutoff, calorie regularity, meal timing variability |
| Mindfulness/stress | minutes per week, sessions per week, breathwork days, stress score, pre/post subjective stress delta, adherence streak |
| PROMs | sleep quality, energy, stress, soreness, mood, illness, travel, shift work, perceived recovery |
| Quality/missingness | coverage, valid nights, PPG quality, stage confidence, device source, source changes, non-wear mask, absent-log mask |

### Transform Rules

- Use robust rolling medians and median absolute deviation for physiology baselines.
- Winsorize continuous wearable features at source- and age-stratified bounds before model inference.
- Encode missingness reason as categorical features: `non_wear`, `low_signal_quality`, `not_logged`, `not_supported`, `not_requested`.
- Keep population-normalized features and personal-baseline deltas side by side. Example: `rmssd_night_28d_percentile_age_sex_source` and `rmssd_night_28d_delta_vs_user_84d`.
- Treat source/device family as a calibration feature, not as a user-facing driver.

## Model Architecture

The model should be hierarchical and multitask:

1. Sleep Core submodels produce sleep-domain latent scores and Sleep Age.
2. Domain models produce training, nutrition, mindfulness, stress, and biomarker latent scores when data exists.
3. A fusion model estimates stable Biological Age and Pace of Aging with sleep given structural priority.
4. Calibration and uncertainty layers transform raw predictions into product-safe intervals, confidence, and no-score decisions.

### Suggested Modeling Stack

| Layer | Baseline | Recommended production model | Optional advanced model |
| --- | --- | --- | --- |
| Sleep submodels | constrained GAMs with monotonic terms | LightGBM or XGBoost with monotonic constraints plus SHAP | temporal convolution or transformer over nightly sequences |
| Multimodal fusion | elastic net residual model over chronological age | gradient boosting multitask model plus source calibration | sequence model pretrained on wearable history |
| Personalization | rolling robust z-scores and empirical Bayes shrinkage | hierarchical state-space smoothing of user baseline and trend | user-adaptive latent state model |
| Uncertainty | rule-based coverage score plus residual SD | conformal prediction by source/coverage strata | deep ensembles plus conformal calibration |
| Explanations | signed feature deltas | SHAP or monotonic contribution ledger grouped by domain | counterfactual simulator constrained to low-risk behavior changes |

Training targets should be multitask:

- Chronological age as a weak pretraining target.
- KDM Biological Age and PhenoAge when lab cohorts exist.
- Pace labels from longitudinal change, not just cross-sectional age.
- Future functional proxies such as resting HR trend, HRV trend, sleep regularity deterioration, subjective energy, and recovery stability.
- Product responsiveness labels from sustained behavior changes in 2 to 8 week windows.

## Sleep Core Design

Sleep should be the dominant signal because it is high frequency, modifiable, longitudinal, and central to recovery physiology.

### Sleep Submodels

| Submodel | Inputs | Output |
| --- | --- | --- |
| Autonomic recovery | HRV, HR, RHR, respiratory rate, temperature, SpO2, PPG quality | `autonomic_recovery_score`, `autonomic_age_gap` |
| Architecture | REM %, deep %, N3/REM timing, stage entropy, stage confidence | `sleep_architecture_score`, `architecture_age_gap` |
| Continuity | efficiency, WASO, awakenings, fragmentation, bout length | `sleep_continuity_score`, `continuity_age_gap` |
| Circadian timing | midpoint SD, bedtime SD, wake SD, social jetlag, target alignment | `circadian_regularity_score`, `circadian_age_gap` |
| Resilience | post-load sleep response, alcohol/caffeine/late meal response, stress recovery slope | `sleep_resilience_score`, `resilience_age_gap` |

### Sleep Age Pseudocode

```python
def sleep_age(input, model, calibration):
    components = {
        "autonomic": model.autonomic.predict(input.sleep, input.quality),
        "architecture": model.architecture.predict(input.sleep, input.quality),
        "continuity": model.continuity.predict(input.sleep, input.quality),
        "circadian": model.circadian.predict(input.sleep, input.quality),
        "resilience": model.resilience.predict(input.sleep, input.training, input.nutrition, input.proms)
    }

    available = {k: v for k, v in components.items() if v.is_available}
    masks = missingness_masks(input)
    raw_sleep_gap = model.sleep_meta.predict(available, masks, source=input.source_mix)

    # Shrink when coverage or stage confidence is low. Do not fabricate stages.
    shrink = calibration.sleep_shrinkage(input.quality, masks)
    calibrated_gap = calibration.sleep_age_gap(raw_sleep_gap, shrink)

    return SleepAgeResult(
        years=input.chronological_age + calibrated_gap,
        gap_years=calibrated_gap,
        components=available,
        missingness=masks
    )
```

Design constraints:

- Architecture can only contribute when stage confidence is sufficient.
- Missing stage data lowers confidence but does not block Sleep Age.
- Duration alone can never create a high-confidence young Sleep Age.
- Circadian regularity and continuity should remain influential even when duration is adequate.
- Sleep resilience should compare current behavior to the user's own baseline whenever possible.

## Fusion Strategy

Biological Age is not a simple average of sleep, training, nutrition, and mindfulness scores. It should estimate a latent functional age gap with sleep as the primary observed pathway.

### Biological Age Formula

The production model should predict an age gap, then smooth and calibrate it.

```python
sleep_gap = sleep_age_result.gap_years
non_sleep_features = build_non_sleep_feature_vector(training, nutrition, mindfulness, biomarkers, proms)
quality = build_quality_vector(input)

raw_gap = fusion_model.predict(
    chronological_age=input.chronological_age,
    sleep_gap=sleep_gap,
    sleep_components=sleep_age_result.components,
    non_sleep=non_sleep_features,
    missingness=input.missingness,
    source=input.source_mix,
    quality=quality
)

# Structural priority: sleep anchors at least 55% of explainable contribution
# unless sleep coverage is invalid. Other domains can modulate but not drown it.
priority_gap = enforce_sleep_priority(
    raw_gap=raw_gap,
    sleep_gap=sleep_gap,
    sleep_valid=input.sleep.nights_valid_28d >= 14,
    minimum_sleep_share=0.55
)

stable_gap = state_space_smoother.update(
    user_id=input.user_id,
    date=input.date,
    observed_gap=priority_gap,
    observation_variance=uncertainty.observation_variance(input)
)

biological_age = input.chronological_age + stable_gap
```

### Pace of Aging Formula

Pace should be short-term and responsive, but less noisy than a weekly age difference.

```python
def pace_of_aging(user_state, current_features):
    recent_latent = current_features.latent_gap_7d
    stable_latent = user_state.latent_gap_84d
    behavior_velocity = current_features.sleep_resilience_7d_slope
    recovery_velocity = current_features.autonomic_recovery_7d_slope
    load_penalty = current_features.acute_chronic_load_excess

    raw_pace = pace_model.predict(
        recent_latent=recent_latent,
        stable_latent=stable_latent,
        behavior_velocity=behavior_velocity,
        recovery_velocity=recovery_velocity,
        load_penalty=load_penalty,
        missingness=current_features.missingness
    )

    return clamp(calibrate_pace(raw_pace), 0.65, 1.35)
```

Interpretation:

- `1.00x` means the user's short-term trajectory is aligned with expected baseline.
- `< 1.00x` means recent signals are moving in a favorable direction.
- `> 1.00x` means recent signals are moving in an unfavorable direction.
- Product copy must say "trajectory" or "pace estimate", not "you are aging this fast".

## Personalization

Personalization should be explicit and auditable.

- Use a population model for cold start.
- Add user baselines after at least 21 valid nights or 28 valid days, depending on feature.
- Use empirical Bayes shrinkage so early personal baselines cannot overrule population calibration.
- Keep baseline windows separate:
  - 28 days for actionable recent sleep and training state.
  - 84 days for personal baseline.
  - 180 days for stable biological age smoothing when available.
- Store model state separately from raw health data: `user_id`, `date`, `model_version`, latent gap, variance, baseline metadata, and source mix.
- Reset or reweight baseline after major source changes, timezone relocation, illness flags, pregnancy flags if supported, or shift-work status changes.

## Missing Data Strategy

Missing data is signal. It should never be silently imputed as normal behavior.

| Missing class | Example | Handling |
| --- | --- | --- |
| Non-wear | no overnight data | no fabricated sleep; lower confidence; use available longitudinal state |
| Low signal quality | PPG artifact | mask HRV/HR features; keep duration/regularity if valid |
| Not logged | nutrition absent | include missing-log mask; do not assume alcohol/caffeine/protein are zero |
| Not supported | no sleep stages from source | disable architecture submodel; keep duration, continuity, regularity, physiology |
| Source transition | Apple Watch to Oura | calibration flag; avoid treating jumps as biological change |

No-score rules:

- Do not emit a new Biological Age if fewer than 7 valid sleep nights exist in the last 28 days and no prior stable state exists.
- Emit low-confidence trend-only output if 7 to 13 valid sleep nights exist.
- Emit Sleep Age without architecture if stage data is missing but sleep/wake, timing, and physiology are valid.
- Suppress Pace of Aging if the last 14 days are dominated by non-wear or source transition.

## Calibration and Uncertainty

Uncertainty must be first-class in both API and UX.

### Confidence Score

```python
coverage = weighted_coverage({
    "valid_sleep_nights_28d": input.sleep.nights_valid_28d / 24,
    "physiology_coverage": input.quality.ppg_quality_mean,
    "stage_coverage": input.sleep.stage_confidence_mean,
    "training_coverage": input.training.days_valid_28d / 20,
    "nutrition_coverage": input.nutrition.days_logged_28d / 18,
    "mindfulness_coverage": input.mindfulness.days_valid_28d / 8
})

sleep_priority_coverage = min(1.0, input.sleep.nights_valid_28d / 21) * input.quality.sleep_source_stability
source_penalty = 0.12 if input.quality.source_changed_28d else 0.0
missingness_penalty = model_missingness_penalty(input.missingness)

confidence_score = clamp(
    0.50 * sleep_priority_coverage +
    0.30 * coverage +
    0.20 * model_conformal_reliability -
    source_penalty -
    missingness_penalty
)
```

Confidence levels:

- `high`: score >= 0.80 and conformal interval width <= 4.0 years.
- `moderate`: score >= 0.55.
- `low`: score < 0.55 but valid trend output exists.
- `missing`: no defensible inference.

### Intervals

Use conformal prediction calibrated by source family, coverage level, age decade, and sex when provided. The API should return p10, p50, and p90. If the p90-p10 width exceeds 7 years, the UX should foreground uncertainty and avoid aggressive recommendations.

### Calibration Targets

- Age MAE should be tracked but not optimized alone.
- Clinical-label MAE against KDM/PhenoAge should be tracked in lab cohorts.
- Calibration slope should remain near 1.0 after recalibration.
- Test-retest ICC for stable Biological Age should be >= 0.80.
- Within-person weekly noise should be targeted below 1 year once confidence is high.
- Conformal 90% intervals should cover approximately 90% of held-out labels.

## Inference Logic

```python
def score_biological_age(input: BiologicalAgeInput, model_bundle: ModelBundle) -> BiologicalAgeOutput:
    validate_schema(input)
    qc = run_quality_checks(input)

    if qc.no_score:
        return BiologicalAgeOutput.missing(
            user_id=input.user_id,
            date=input.date,
            quality_flags=qc.flags,
            model_version=model_bundle.version
        )

    features = build_features(input)
    sleep = sleep_age(features, model_bundle.sleep, model_bundle.calibration)
    domain_scores = score_domains(features, model_bundle.domain_models)
    fused = fuse_biological_age(features, sleep, domain_scores, model_bundle)
    pace = score_pace(features, fused, model_bundle)
    interval = model_bundle.uncertainty.predict_interval(features, fused)
    drivers = explain(features, sleep, domain_scores, fused, model_bundle)
    recommendations = recommend_low_risk_actions(drivers, qc)

    return BiologicalAgeOutput(
        biological_age_years=round(fused.p50, 1),
        age_gap_years=round(fused.p50 - input.chronological_age, 1),
        sleep_age_years=round(sleep.years, 1),
        pace_of_aging_x=round(pace, 2),
        confidence=interval.confidence,
        drivers=drivers,
        quality_flags=qc.flags,
        recommendations=recommendations,
        model_version=model_bundle.version
    )
```

### Recommendation Rules

Recommendations must be limited to low-risk behavior support:

- Improve sleep timing regularity.
- Reduce caffeine late in the day.
- Avoid late heavy meals near bedtime.
- Balance high-intensity training with recovery.
- Maintain effective sleep and HRV habits.
- Use mindfulness or breathing sessions as stress-regulation support.

Recommendations must not mention diagnosis, disease treatment, apnea detection, cardiovascular disease prediction, or medication decisions.

## JSON Contracts

### Example Input

```json
{
  "schema_version": "bioage.input.v1",
  "user_id": "u_123",
  "date": "2026-06-20",
  "chronological_age": 36.4,
  "sleep": {
    "nights_valid_28d": 24,
    "total_sleep_time_min_28d_mean": 420,
    "sleep_efficiency_28d_mean": 0.89,
    "waso_min_28d_mean": 42,
    "sleep_midpoint_sd_min_28d": 38,
    "rem_pct_28d_mean": 0.21,
    "deep_pct_28d_mean": 0.18,
    "rmssd_night_28d_median": 41.2,
    "hr_night_min_28d_mean": 52,
    "stage_confidence_mean": 0.81,
    "ppg_quality_mean": 0.87
  },
  "training": {
    "days_valid_28d": 22,
    "strain_28d_mean": 11.4,
    "zone2_min_week_mean": 146,
    "zone45_min_week_mean": 31,
    "strength_sessions_week_mean": 2.1,
    "steps_28d_mean": 9200
  },
  "nutrition": {
    "days_logged_28d": 19,
    "protein_g_day_28d_mean": 96,
    "fiber_g_day_28d_mean": 24,
    "alcohol_days_week_mean": 1.8,
    "late_meal_days_week_mean": 2.5,
    "caffeine_after_2pm_days_week_mean": 3.2
  },
  "mindfulness": {
    "days_valid_28d": 12,
    "minutes_week_mean": 56,
    "sessions_week_mean": 4.0
  },
  "proms": {
    "sleep_quality_28d_mean": 3.9,
    "energy_28d_mean": 3.7,
    "stress_28d_mean": 2.8
  },
  "quality": {
    "source_changed_28d": false,
    "sleep_source_stability": 0.95
  }
}
```

### Example Output

```json
{
  "schema_version": "bioage.output.v1",
  "model_version": "pulsar-bioage-sleepfirst-1.0.0",
  "user_id": "u_123",
  "date": "2026-06-20",
  "biological_age_years": 34.8,
  "age_gap_years": -1.6,
  "pace_of_aging_x": 0.82,
  "sleep_age_years": 33.9,
  "confidence": {
    "level": "high",
    "score": 0.86,
    "p10": 33.7,
    "p50": 34.8,
    "p90": 36.2
  },
  "drivers": [
    {
      "feature": "sleep_midpoint_sd_min_28d",
      "domain": "sleep_circadian",
      "direction": "older",
      "impact_years": 0.6
    },
    {
      "feature": "rmssd_night_28d_median",
      "domain": "sleep_autonomic",
      "direction": "younger",
      "impact_years": -0.8
    },
    {
      "feature": "zone2_min_week_mean",
      "domain": "training",
      "direction": "younger",
      "impact_years": -0.3
    }
  ],
  "quality_flags": [
    "sleep_staging_available",
    "ppg_quality_ok",
    "source_stable"
  ],
  "recommendations": [
    "Reduce sleep timing variability below 30 minutes.",
    "Maintain current nocturnal HRV trend.",
    "Avoid late meals before high-load training days."
  ]
}
```

## Test Cases

### Unit Tests

- Complete high-quality sleep data produces high confidence and includes architecture, continuity, circadian, autonomic, and resilience subscores.
- No sleep stage data but valid duration, regularity, continuity, HRV, and HR produces a valid Sleep Age with lower confidence and `sleep_staging_missing`.
- Sparse training with very good sleep keeps sleep dominant and does not over-penalize absent training logs.
- Irregular sleep timing with adequate duration produces an older circadian driver and recommendation focused on timing variability.
- Poor PPG quality with missing HRV masks autonomic features, lowers confidence, and avoids fabricated HRV explanations.
- Sudden 14-day deterioration after high training load moves Pace of Aging before it materially moves stable Biological Age.
- Population score differs from personal-baseline score when a user's current values are healthy relative to population but worse than their own 84-day baseline.
- Source transition creates a calibration flag and reduces short-term trend confidence.
- Nutrition absent because of no logging is not interpreted as zero alcohol or zero caffeine.
- The same input plus same model seed produces byte-stable output.

### Integration Tests

- Swift `LabModuleStore` can map current `DailyStrainRecord`, `SleepSummary`, `RecoverySummary`, nutrition, mindfulness, and biomarkers into `bioage.input.v1`.
- The scoring service returns `bioage.output.v1`, and the app can map it into an extended Lab result without losing existing historical results.
- Existing `BiologicalAgeResult` history remains readable when the new model is disabled.
- Feature extraction correctly handles timezone and DST around sleep date keys.
- Model version changes are persisted with each result.

### Validation Tests

- Retrospective holdout by user, not by row.
- Device/source-stratified calibration reports.
- Ablation: sleep-only, non-sleep-only, and sleep-first fusion.
- Responsiveness analysis for 2, 4, and 8 week sustained sleep improvements.
- Conformal interval coverage by confidence tier.

## Migration Plan

### Current State

`LabBiologicalAgeEngine` currently:

- Requires chronological age.
- Computes physiological, lifestyle, and biomarker scores.
- Redistributes fixed pillar weights across available pillars.
- Converts pillar scores into contribution-years.
- Applies confidence-based shrinkage and caps.
- Stores `BiologicalAgeResult` history in `pulsar.lab.biologicalAgeHistory.v1`.
- Computes `paceOfAging` later in `LabModuleStore` from changes in `ageDelta`.

This is a reasonable MVP, but it is not the new target paradigm.

### Phase 1: Add Contracts and Feature Builder

- Add `BiologicalAgeScoringInputV1` and `BiologicalAgeScoringOutputV1` models, initially in Swift for app mapping and in Python for reference scoring.
- Build a mapper from current Pulsar data:
  - `SleepSummary` and sleep history for duration, continuity, stage, and regularity features.
  - `RecoverySummary` for nocturnal HR, HRV, respiratory, SpO2, and temperature features.
  - `StrainSummary` and `DailyStrainRecord` for training load and load-response features.
  - Nutrition and mindfulness stores when available.
  - `LabBiomarker` for optional clinical anchors.
- Keep the old Lab engine behind a feature flag as `legacy_lab_age_v1`.

### Phase 2: Reference Python Package

Recommended package structure:

```text
pulsar_bioage/
  pyproject.toml
  README.md
  pulsar_bioage/
    __init__.py
    schemas.py
    quality.py
    features/
      __init__.py
      sleep.py
      training.py
      nutrition.py
      mindfulness.py
      biomarkers.py
      baselines.py
    models/
      __init__.py
      sleep_core.py
      fusion.py
      pace.py
      calibration.py
      uncertainty.py
    inference.py
    explanation.py
    recommendations.py
    registry.py
  tests/
    test_sleep_core.py
    test_missingness.py
    test_fusion_priority.py
    test_pace.py
    test_contracts.py
    test_determinism.py
```

Minimum interfaces:

```python
@dataclass(frozen=True)
class BiologicalAgeInput:
    schema_version: str
    user_id: str
    date: date
    chronological_age: float
    sleep: SleepFeatures
    training: TrainingFeatures
    nutrition: NutritionFeatures
    mindfulness: MindfulnessFeatures
    proms: PromFeatures
    quality: QualityFeatures
    missingness: MissingnessFeatures

@dataclass(frozen=True)
class BiologicalAgeOutput:
    schema_version: str
    model_version: str
    user_id: str
    date: date
    biological_age_years: float | None
    age_gap_years: float | None
    pace_of_aging_x: float | None
    sleep_age_years: float | None
    confidence: ConfidenceOutput
    drivers: list[Driver]
    quality_flags: list[str]
    recommendations: list[str]
```

### Phase 3: Shadow Deployment

- Run legacy and sleep-first outputs side by side for at least 8 weeks.
- Persist new results under a separate history key, for example `pulsar.lab.biologicalAgeHistory.sleepFirst.v1`.
- Show the legacy result in production while collecting local debug comparisons for internal builds.
- Monitor score stability, confidence distribution, missingness, source changes, and driver consistency.

### Phase 4: UX Cutover

- Rename or explain the old result as "Lab Biological Age Preview" during migration if both engines are visible.
- Promote sleep-first Biological Age only when confidence and interval coverage are acceptable.
- Add `sleep_age_years`, `pace_of_aging_x`, interval, drivers, and quality flags to the Lab UI.
- Avoid copy such as "your real body age." Use "Pulsar estimates a wellness age trend from sleep-first physiological signals."

### Phase 5: Retire Legacy Engine

- Keep a decoder for `BiologicalAgeResult` v1 history.
- Migrate history display by model version, not by overwriting old records.
- Keep legacy score available in debug or internal analysis until product metrics confirm the new model is stable.

## Sources And Evidence Notes

- The local technical report supplied with this task recommends a sleep-first, multimodal, uncertainty-aware biological age system and explicitly calls out WHOOP Age/Pace, Oura Cardiovascular Age, KDM, PhenoAge, DunedinPACE, PpgAge, and sleep-health literature as grounding references.
- Use the AASM/Sleep Research Society adult sleep-duration consensus for baseline sleep-duration language.
- Use FDA general wellness guidance and equivalent regional reviews to keep claims in low-risk wellness territory.
- Use FHIR Observation mappings only for traceable clinical or quasi-clinical measurements, not for arbitrary app explanations.
- Validate any user-facing scientific copy against current primary sources before launch.

Starting references from the supplied report:

- KDM biological age: https://pubmed.ncbi.nlm.nih.gov/16318865/
- Sleep health framework: https://pmc.ncbi.nlm.nih.gov/articles/PMC3902880/
- Adult sleep duration consensus: https://pmc.ncbi.nlm.nih.gov/articles/PMC4434546/
- PhenoAge: https://pmc.ncbi.nlm.nih.gov/articles/PMC5940111/
- DunedinPACE: https://pmc.ncbi.nlm.nih.gov/articles/PMC8853656/
- Sleep regularity and mortality: https://pmc.ncbi.nlm.nih.gov/articles/PMC10782501/
- Oura Cardiovascular Age: https://support.ouraring.com/hc/articles/28451491040019-Cardiovascular-Age
- FHIR Observation: https://build.fhir.org/observation.html
- FDA general wellness policy: https://www.fda.gov/regulatory-information/search-fda-guidance-documents/general-wellness-policy-low-risk-devices
