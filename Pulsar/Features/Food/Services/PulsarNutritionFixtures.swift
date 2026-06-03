//
//  PulsarNutritionFixtures.swift
//  Pulsar
//

import Foundation

enum PulsarNutritionFixtures {
    static let oats = PulsarFoodItem(
        name: "Overnight Oats",
        detail: "Oats, yogurt, berries",
        serving: PulsarNutritionServing(amount: 1, unit: "bowl", grams: 320),
        nutritionPerServing: PulsarNutritionFacts(
            calories: 410,
            protein: 24,
            carbohydrates: 58,
            fat: 10,
            fiber: 11,
            sugar: 15,
            sodiumMilligrams: 130
        ),
        source: .savedFood,
        isSaved: true
    )

    static let eggsToast = PulsarFoodItem(
        name: "Eggs and Sourdough",
        detail: "Two eggs, toast, avocado",
        serving: PulsarNutritionServing(amount: 1, unit: "plate", grams: 280),
        nutritionPerServing: PulsarNutritionFacts(
            calories: 520,
            protein: 28,
            carbohydrates: 42,
            fat: 25,
            fiber: 9,
            sugar: 4,
            sodiumMilligrams: 540
        ),
        source: .savedFood,
        isSaved: true
    )

    static let salmonBowl = PulsarFoodItem(
        name: "Salmon Grain Bowl",
        detail: "Salmon, rice, greens, tahini",
        serving: PulsarNutritionServing(amount: 1, unit: "bowl", grams: 430),
        nutritionPerServing: PulsarNutritionFacts(
            calories: 720,
            protein: 46,
            carbohydrates: 64,
            fat: 29,
            fiber: 10,
            sugar: 7,
            sodiumMilligrams: 760
        ),
        source: .savedFood,
        isSaved: true
    )

    static let chickenWrap = PulsarFoodItem(
        name: "Chicken Herb Wrap",
        detail: "Chicken, greens, yogurt sauce",
        serving: PulsarNutritionServing(amount: 1, unit: "wrap", grams: 310),
        nutritionPerServing: PulsarNutritionFacts(
            calories: 560,
            protein: 42,
            carbohydrates: 52,
            fat: 18,
            fiber: 8,
            sugar: 5,
            sodiumMilligrams: 680
        ),
        source: .savedFood,
        isSaved: true
    )

    static let greekYogurt = PulsarFoodItem(
        name: "Greek Yogurt",
        detail: "Plain yogurt, fruit optional",
        serving: PulsarNutritionServing(amount: 1, unit: "cup", grams: 225),
        nutritionPerServing: PulsarNutritionFacts(
            calories: 160,
            protein: 23,
            carbohydrates: 10,
            fat: 4,
            fiber: 0,
            sugar: 8,
            sodiumMilligrams: 80
        ),
        source: .savedFood,
        isSaved: true
    )

    static let recoveryShake = PulsarFoodItem(
        name: "Recovery Shake",
        detail: "Protein, banana, oat milk",
        serving: PulsarNutritionServing(amount: 1, unit: "shake", grams: 420),
        nutritionPerServing: PulsarNutritionFacts(
            calories: 390,
            protein: 36,
            carbohydrates: 46,
            fat: 7,
            fiber: 6,
            sugar: 22,
            sodiumMilligrams: 250
        ),
        source: .savedFood,
        isSaved: true
    )

    static let lentilSoup = PulsarFoodItem(
        name: "Lentil Soup",
        detail: "Lentils, vegetables, olive oil",
        serving: PulsarNutritionServing(amount: 1, unit: "bowl", grams: 360),
        nutritionPerServing: PulsarNutritionFacts(
            calories: 430,
            protein: 24,
            carbohydrates: 56,
            fat: 12,
            fiber: 17,
            sugar: 8,
            sodiumMilligrams: 620
        ),
        source: .savedFood,
        isSaved: true
    )

    static let tofuRice = PulsarFoodItem(
        name: "Tofu Rice Plate",
        detail: "Tofu, rice, greens, sesame",
        serving: PulsarNutritionServing(amount: 1, unit: "plate", grams: 390),
        nutritionPerServing: PulsarNutritionFacts(
            calories: 610,
            protein: 31,
            carbohydrates: 72,
            fat: 21,
            fiber: 9,
            sugar: 6,
            sodiumMilligrams: 700
        ),
        source: .savedFood,
        isSaved: true
    )

    static let almonds = PulsarFoodItem(
        name: "Almonds",
        detail: "Simple snack",
        serving: PulsarNutritionServing(amount: 1, unit: "handful", grams: 28),
        nutritionPerServing: PulsarNutritionFacts(
            calories: 165,
            protein: 6,
            carbohydrates: 6,
            fat: 14,
            fiber: 4,
            sugar: 1,
            sodiumMilligrams: 0
        ),
        source: .savedFood,
        isSaved: true
    )

    static let searchFoods: [PulsarFoodItem] = [
        oats,
        eggsToast,
        salmonBowl,
        chickenWrap,
        greekYogurt,
        recoveryShake,
        lentilSoup,
        tofuRice,
        almonds,
        PulsarFoodItem(
            name: "Berry Smoothie",
            detail: "Berries, protein, coconut water",
            serving: PulsarNutritionServing(amount: 1, unit: "smoothie", grams: 380),
            nutritionPerServing: PulsarNutritionFacts(
                calories: 310,
                protein: 26,
                carbohydrates: 43,
                fat: 4,
                fiber: 8,
                sugar: 24,
                sodiumMilligrams: 120
            ),
            source: .savedFood,
            isSaved: true
        ),
        PulsarFoodItem(
            name: "Quinoa Greens",
            detail: "Quinoa, greens, chickpeas",
            serving: PulsarNutritionServing(amount: 1, unit: "bowl", grams: 410),
            nutritionPerServing: PulsarNutritionFacts(
                calories: 590,
                protein: 27,
                carbohydrates: 78,
                fat: 18,
                fiber: 15,
                sugar: 8,
                sodiumMilligrams: 520
            ),
            source: .savedFood,
            isSaved: true
        )
    ]

    static let commonFoods = searchFoods

    static func seedState(now: Date, calendar: Calendar) -> PulsarNutritionState {
        let startOfDay = calendar.startOfDay(for: now)
        let todayEntries = [
            PulsarNutritionEntry(
                food: oats,
                servingMultiplier: 1,
                mealMoment: .breakfast,
                loggedAt: date(on: startOfDay, hour: 8, minute: 12, calendar: calendar),
                source: .savedFood
            ),
            PulsarNutritionEntry(
                food: salmonBowl,
                servingMultiplier: 0.9,
                mealMoment: .lunch,
                loggedAt: date(on: startOfDay, hour: 13, minute: 4, calendar: calendar),
                source: .savedFood
            ),
            PulsarNutritionEntry(
                food: recoveryShake,
                servingMultiplier: 1,
                mealMoment: .snacks,
                loggedAt: date(on: startOfDay, hour: 17, minute: 42, calendar: calendar),
                confidence: 0.9,
                source: .quickEstimate
            )
        ]

        let previousEntries = (1...6).flatMap { offset -> [PulsarNutritionEntry] in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfDay) else { return [] }
            let morningFood = offset.isMultiple(of: 2) ? eggsToast : oats
            let middayFood = offset.isMultiple(of: 3) ? tofuRice : chickenWrap
            let eveningFood = offset.isMultiple(of: 2) ? lentilSoup : salmonBowl
            return [
                PulsarNutritionEntry(
                    food: morningFood,
                    servingMultiplier: 1,
                    mealMoment: .breakfast,
                    loggedAt: date(on: day, hour: 8, minute: 6 + offset, calendar: calendar),
                    source: .savedFood
                ),
                PulsarNutritionEntry(
                    food: middayFood,
                    servingMultiplier: 1,
                    mealMoment: .lunch,
                    loggedAt: date(on: day, hour: 12, minute: 50 + offset, calendar: calendar),
                    source: .savedFood
                ),
                PulsarNutritionEntry(
                    food: eveningFood,
                    servingMultiplier: offset.isMultiple(of: 2) ? 1 : 0.82,
                    mealMoment: .dinner,
                    loggedAt: date(on: day, hour: 19, minute: 4 + offset, calendar: calendar),
                    source: .savedFood
                )
            ]
        }

        let hydrationEntries = [
            PulsarHydrationEntry(amountMilliliters: 350, loggedAt: date(on: startOfDay, hour: 7, minute: 30, calendar: calendar)),
            PulsarHydrationEntry(amountMilliliters: 500, loggedAt: date(on: startOfDay, hour: 11, minute: 10, calendar: calendar)),
            PulsarHydrationEntry(amountMilliliters: 350, loggedAt: date(on: startOfDay, hour: 15, minute: 38, calendar: calendar))
        ] + (1...6).flatMap { offset -> [PulsarHydrationEntry] in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfDay) else { return [] }
            return [
                PulsarHydrationEntry(amountMilliliters: 500, loggedAt: date(on: day, hour: 9, minute: 0, calendar: calendar)),
                PulsarHydrationEntry(amountMilliliters: Double(900 + offset * 80), loggedAt: date(on: day, hour: 14, minute: 20, calendar: calendar)),
                PulsarHydrationEntry(amountMilliliters: 450, loggedAt: date(on: day, hour: 19, minute: 35, calendar: calendar))
            ]
        }

        let privateFoods = [
            PulsarFoodItem(
                name: "House Protein Bowl",
                detail: "Local private food",
                serving: PulsarNutritionServing(amount: 1, unit: "bowl", grams: 430),
                nutritionPerServing: PulsarNutritionFacts(
                    calories: 650,
                    protein: 52,
                    carbohydrates: 54,
                    fat: 20,
                    fiber: 9,
                    sugar: 6,
                    sodiumMilligrams: 710
                ),
                source: .privateFood,
                isSaved: true
            )
        ]

        let templates = [
            PulsarMealTemplate(
                name: "Steady Morning",
                defaultMoment: .breakfast,
                items: [
                    PulsarMealTemplateItem(food: greekYogurt, servingMultiplier: 1),
                    PulsarMealTemplateItem(food: almonds, servingMultiplier: 0.7)
                ]
            ),
            PulsarMealTemplate(
                name: "Recovery Anchor",
                defaultMoment: .snacks,
                items: [
                    PulsarMealTemplateItem(food: recoveryShake, servingMultiplier: 1),
                    PulsarMealTemplateItem(food: greekYogurt, servingMultiplier: 0.5)
                ]
            )
        ]

        let recipe = PulsarRecipe(
            name: "Lentil Recovery Stew",
            servings: 3,
            ingredients: [
                PulsarRecipeIngredient(food: lentilSoup, servingMultiplier: 2),
                PulsarRecipeIngredient(food: greekYogurt, servingMultiplier: 0.5)
            ],
            note: "Batch-friendly and fiber-forward."
        )

        let checkIns = [
            PulsarBodyCheckIn(
                date: startOfDay,
                weightKilograms: 72.4,
                waistCentimeters: 81.5,
                bodyFatPercentage: nil,
                note: "Weekly nutrition context."
            ),
            PulsarBodyCheckIn(
                date: calendar.date(byAdding: .day, value: -7, to: startOfDay) ?? startOfDay,
                weightKilograms: 72.9,
                waistCentimeters: 82.1
            )
        ]

        let context = PulsarNutritionRecoveryContext.mock
        let target = PulsarNutritionTargetSnapshot(
            date: now,
            fuelRange: 2130...2490,
            proteinRange: (118 + context.proteinAdjustmentGrams)...(146 + context.proteinAdjustmentGrams),
            fiberTarget: 28,
            hydrationTargetMilliliters: 2400 + context.hydrationAdjustmentMilliliters,
            recoveryScore: context.recoveryScore,
            activityLoad: context.activityLoad,
            rationale: "Mock Pulsar context is active until real HealthKit, Oura, and Fitness nutrition hooks are connected."
        )

        return PulsarNutritionState(
            entries: todayEntries + previousEntries,
            hydrationEntries: hydrationEntries,
            privateFoods: privateFoods,
            mealTemplates: templates,
            recipes: [recipe],
            bodyCheckIns: checkIns,
            targetSnapshots: [target],
            eatingWindow: .default
        )
    }

    private static func date(on startOfDay: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: startOfDay) ?? startOfDay
    }
}
