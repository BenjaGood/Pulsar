//
//  FreeExerciseDBServiceTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct FreeExerciseDBServiceTests {
    @Test func normalizesMetadataImagesAndSource() throws {
        let exercises = try FreeExerciseDBService.decodeCatalog(from: Data(Self.benchPressJSON.utf8))
        let exercise = try #require(exercises.first)

        #expect(exercise.id == "free-exercise-db-Barbell_Bench_Press_-_Medium_Grip")
        #expect(exercise.name == "Barbell Bench Press - Medium Grip")
        #expect(exercise.primaryMuscleGroup == .chest)
        #expect(exercise.primaryMuscles.map(\.name) == ["Chest"])
        #expect(exercise.secondaryMuscles.map(\.group) == [.shoulders, .triceps])
        #expect(exercise.equipmentSummary == "Barbell")
        #expect(exercise.category == "Strength")
        #expect(exercise.level == "Beginner")
        #expect(exercise.force == "Push")
        #expect(exercise.mechanic == "Compound")
        #expect(exercise.thumbnailURL == "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/Barbell_Bench_Press_-_Medium_Grip/0.jpg")
        #expect(exercise.imageURLs.count == 2)
        #expect(exercise.dataSource == "free-exercise-db")
        #expect(exercise.dataSourceURL == "https://github.com/yuhonas/free-exercise-db")
        #expect(exercise.license == "Unlicense")
    }

    @Test func mapsFreeExerciseDBMuscleNamesToPulsarGroups() throws {
        let exercises = try FreeExerciseDBService.decodeCatalog(from: Data(Self.pullJSON.utf8))
        let exercise = try #require(exercises.first)

        #expect(exercise.primaryMuscles.map(\.group) == [.lats, .upperMiddleBack, .lowerBack])
        #expect(exercise.secondaryMuscles.map(\.group) == [.traps, .neckTraps, .biceps])
    }

    @Test func handlesNullEquipmentAndMissingImagesGracefully() throws {
        let exercises = try FreeExerciseDBService.decodeCatalog(from: Data(Self.nullsJSON.utf8))
        let exercise = try #require(exercises.first)

        #expect(exercise.equipmentSummary == "Bodyweight")
        #expect(exercise.thumbnailURL == nil)
        #expect(exercise.imageURLs.isEmpty)
        #expect(exercise.force == nil)
        #expect(exercise.mechanic == nil)
    }

    private static let benchPressJSON = """
    [
      {
        "id": "Barbell_Bench_Press_-_Medium_Grip",
        "name": "Barbell Bench Press - Medium Grip",
        "force": "push",
        "level": "beginner",
        "mechanic": "compound",
        "equipment": "barbell",
        "primaryMuscles": ["chest"],
        "secondaryMuscles": ["shoulders", "triceps"],
        "instructions": ["Lie on the bench.", "Press the bar."],
        "category": "strength",
        "images": ["Barbell_Bench_Press_-_Medium_Grip/0.jpg", "Barbell_Bench_Press_-_Medium_Grip/1.jpg"]
      }
    ]
    """

    private static let pullJSON = """
    [
      {
        "id": "Back_Mapper",
        "name": "Back Mapper",
        "force": "pull",
        "level": "intermediate",
        "mechanic": "compound",
        "equipment": "cable",
        "primaryMuscles": ["lats", "middle back", "lower back"],
        "secondaryMuscles": ["traps", "neck", "biceps"],
        "instructions": [],
        "category": "strength",
        "images": []
      }
    ]
    """

    private static let nullsJSON = """
    [
      {
        "id": "Adductor_Groin",
        "name": "Adductor/Groin",
        "force": null,
        "level": "beginner",
        "mechanic": null,
        "equipment": null,
        "primaryMuscles": ["adductors"],
        "secondaryMuscles": [],
        "instructions": [],
        "category": "stretching",
        "images": []
      }
    ]
    """
}
