# Orion Nutritional Calculation

Guideline version: `2026.07-v1`

## Product boundary

Orion Nutritional Calculation is an adult informational planning tool. It is not a diagnostic device, a therapeutic diet generator, or a replacement for a registered dietitian or clinician. The deterministic engine owns every numeric target. Orion AI can explain a validated result but cannot supply or replace calories, macros, fiber, hydration, or micronutrient values.

The current release blocks generic target generation during pregnancy or breastfeeding. Those life stages require details and clinical context that this flow does not collect. It also rejects ages outside 18–100, heights outside 120–230 cm, and weights outside 35–300 kg.

## Inputs and privacy

The flow can prefill age, biological sex, height, weight, unit preference, and training level from `UserProfile`. A recent manual body check-in can provide weight and body-fat percentage. HealthKit is reduced on-device to a maximum 28-day aggregate:

- observed days and coverage;
- mean steps, active energy, basal energy, exercise minutes, and walking/running distance;
- workout count, duration, and workout energy;
- most recent weight and body-fat percentage for user confirmation.

Raw samples, names, device identifiers, GPS, and complete local databases are not sent to Orion. The optional explanation request contains only user-confirmed calculator inputs, the aggregate activity summary, and the validated deterministic result. The app contains no OpenAI API key; the existing trusted Orion proxy owns provider credentials and model selection.

## Deterministic method

### 1. Input validation

Plausible body fat is currently 5–60%. Values outside that band are ignored with a visible limitation, causing the engine to use Mifflin–St Jeor. Training sessions are clamped to 0–14 per week. Metric values are canonical in persistence.

### 2. Resting energy

When plausible body fat is unavailable, the engine uses Mifflin–St Jeor:

```text
male:   10W + 6.25H - 5A + 5
female: 10W + 6.25H - 5A - 161
```

`W` is kilograms, `H` is centimeters, and `A` is years. The original equation was developed from measured resting energy expenditure in healthy adults: [Mifflin et al., 1990](https://pubmed.ncbi.nlm.nih.gov/2305711/).

When plausible body fat is available, the engine uses the Katch–McArdle lean-mass form:

```text
lean mass kg = weight kg × (1 - body-fat fraction)
BMR = 370 + 21.6 × lean mass kg
```

Consumer body-fat estimates are noisy, so the formula choice and limitation remain visible. If biological sex is `Other` or `Not set`, the current Mifflin implementation uses the midpoint of the published male and female constants and adds a lower-confidence limitation. That midpoint is a transparent product fallback, not a separately validated equation.

### 3. Maintenance energy

The modeled path multiplies BMR by an activity factor derived from steps, confirmed training sessions, and primary training type. The factor is bounded to 1.20–1.90.

When at least 14 observed days include plausible basal energy, maintenance blends:

```text
70% × mean HealthKit (basal + active energy)
+ 30% × modeled BMR/activity estimate
```

This 70/30 blend and the 8%/14% uncertainty bands are Pulsar product rules. They are not clinical standards. Their purpose is to avoid treating wearable energy as ground truth while still using an adequate personal history. With fewer than 14 days, only the modeled path is used and confidence is reduced.

### 4. Goal adjustment and safety rails

Pace options correspond to 0.25%, 0.50%, or 0.75% of body weight per week. The engine uses 7,700 kcal/kg only as a planning approximation, then applies conservative clamps:

- fat loss: 200–750 kcal/day deficit;
- recomposition: 75–150 kcal/day deficit near maintenance;
- muscle gain: 150–400 kcal/day surplus;
- maintenance: no adjustment.

The lower calorie rail is the greater of 86% of estimated BMR or 1,200 kcal for female, 1,500 kcal for male, and 1,350 kcal for the neutral fallback. These are soft product guardrails, not proof that an intake is medically appropriate.

### 5. Macronutrients

Protein is allocated first:

- fat loss or recomposition: 2.0 g/kg;
- muscle gain: 1.8 g/kg;
- maintenance: 1.6 g/kg.

These values sit within or near the International Society of Sports Nutrition position that 1.4–2.0 g/kg/day is sufficient for most exercising people: [Jäger et al., 2017](https://jissn.biomedcentral.com/articles/10.1186/s12970-017-0177-8).

Fat is the greater of 0.7 g/kg or 22% of energy. If energy is constrained, the fallback floor is the greater of 0.6 g/kg or 20% of energy. Carbohydrates receive remaining energy after protein and fat. Every macro is non-negative, each result includes a ±10% practical range, and tests check calorie reconciliation after gram rounding.

### 6. Fiber and hydration

Fiber uses 14 g per 1,000 kcal with a product floor of 25 g for female and neutral profiles and 30 g for male profiles. The 14 g/1,000 kcal basis comes from the Dietary Reference Intake framework: [National Academies DRI report](https://nap.nationalacademies.org/catalog/10490/dietary-reference-intakes-for-energy-carbohydrate-fiber-fat-fatty-acids-cholesterol-protein-and-amino-acids).

Hydration is:

```text
35 ml/kg body weight + 7 ml × mean daily exercise minutes
```

The result is rounded to 50 ml. This is a planning heuristic, not a sweat-rate prescription. Climate, altitude, illness, pregnancy, medications, kidney/cardiac conditions, and individual sweat losses can materially change needs.

### 7. Focused micronutrient references

The initial engine includes sodium, potassium, calcium, iron, magnesium, vitamin D, vitamin B12, and folate. Values are food-pattern references, not supplement prescriptions. Current values are based on NIH Office of Dietary Supplements/NASEM DRI tables, including [potassium](https://ods.od.nih.gov/factsheets/Potassium-HealthProfessional/), [magnesium](https://ods.od.nih.gov/factsheets/Magnesium-HealthProfessional/), [folate](https://ods.od.nih.gov/factsheets/Folate-HealthProfessional/), and the [pregnancy/life-stage table](https://ods.od.nih.gov/factsheets/Pregnancy-HealthProfessional/). Iron explicitly warns against unsupervised supplementation.

### 8. BMI

BMI is `kg / m²` and is shown only under progressive disclosure. The UI uses neutral “reference range” language and states that BMI is a population screening measure, not diagnosis or direct body-composition measurement. The formula and adult threshold context follow the [World Health Organization](https://www.who.int/news-room/fact-sheets/detail/obesity-and-overweight).

## Confidence

- High: at least 21 observed days and basal-energy coverage.
- Moderate: at least 7 observed days.
- Low: fewer than 7 observed days or no activity summary.

Confidence describes input coverage, not biological certainty. Formula choice, conflicting profile/HealthKit weight, sparse history, no workouts, invalid body fat, and non-binary equation limitations are stored or surfaced as result limitations.

## Persistence and dashboard behavior

Nutrition persisted state version 4 adds `savedNutritionalCalculations`. Old states decode the field as an empty array. Target snapshots add optional carbohydrate/fat goals, source, and calculation ID. Old snapshots decode to heuristic source and continue deriving carbohydrates/fat from the legacy percentages.

Saving a calculation replaces only today's target snapshot and persists the full input/result/explanation record. The dashboard prefers stored carbohydrate and fat values, so calorie, protein, carbohydrate, and fat progress update immediately. Deleting the calculation removes its snapshot; the store then reseeds the normal heuristic target.

## Orion explanation contract

The backend route is `POST /api/orion/nutrition-explain` (or `/orion/nutrition-explain` locally). It uses strict structured output with:

- `summary`
- `calorieTargetRationale`
- `macroRationale`
- `activityObservations`
- `practicalRecommendations`
- `dataLimitations`
- `suggestedReassessmentDate`
- `safetyNote`

The prompt explicitly prohibits replacement numbers. The iOS client caps returned text and recommendation counts. AI failure never invalidates or removes the local result.

## Reassessment

Targets should be treated as a starting estimate. Reassess after 2–4 weeks using weight trend, training performance, hunger, recovery, and adherence. Future adaptive prompts must remain non-destructive and require explicit user approval before changing targets.

