//
//  FreeExerciseDBServiceTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct FreeExerciseDBServiceTests {
    @Test func loadsBundledExercisesDatasetAndResolvesLocalMedia() throws {
        let exercises = try ExercisesDatasetService().loadBundledExercises()
        #expect(exercises.count == 1324)

        let exercise = try #require(exercises.first { $0.id == "exercises-dataset-0001" })
        let imageURL = try #require(ExerciseDatasetMediaResolver.url(for: exercise.thumbnailURL))
        let animationURL = try #require(ExerciseDatasetMediaResolver.url(for: exercise.animationURL))
        #expect(imageURL.isFileURL)
        #expect(animationURL.isFileURL)
        #expect(imageURL.lastPathComponent == "0001-2gPfomN.jpg")
        #expect(animationURL.lastPathComponent == "0001-2gPfomN.gif")
    }

    @Test func normalizesMetadataImagesAnimationAndSource() throws {
        let exercises = try ExercisesDatasetService.decodeCatalog(from: Data(Self.benchPressJSON.utf8))
        let exercise = try #require(exercises.first)

        #expect(exercise.id == "exercises-dataset-0025")
        #expect(exercise.name == "Barbell Bench Press")
        #expect(exercise.primaryMuscleGroup == .chest)
        #expect(exercise.primaryMuscles.map(\.name) == ["Pectorals"])
        #expect(exercise.secondaryMuscles.map(\.group) == [.triceps, .shoulders])
        #expect(exercise.equipmentSummary == "Barbell")
        #expect(exercise.category == "Chest")
        #expect(exercise.instructions == "Unrack the bar over your chest.\n\nLower the bar with control.\n\nPress to lockout.")
        #expect(exercise.thumbnailURL == "images/0025-EIeI8Vf.jpg")
        #expect(exercise.animationURL == "videos/0025-EIeI8Vf.gif")
        #expect(exercise.imageURLs == ["images/0025-EIeI8Vf.jpg"])
        #expect(exercise.dataSource == "hasaneyldrm/exercises-dataset")
        #expect(exercise.dataSourceURL == "https://github.com/hasaneyldrm/exercises-dataset")
        #expect(exercise.license == "Educational / non-commercial only")
    }

    @Test func mapsExercisesDatasetMuscleNamesToPulsarGroups() throws {
        let exercises = try ExercisesDatasetService.decodeCatalog(from: Data(Self.pullJSON.utf8))
        let exercise = try #require(exercises.first)

        #expect(exercise.primaryMuscles.map(\.group) == [.lats])
        #expect(exercise.secondaryMuscles.map(\.group) == [.upperMiddleBack, .lowerBack, .biceps, .forearms])
    }

    @Test func handlesMissingEquipmentInstructionsAndMediaGracefully() throws {
        let exercises = try ExercisesDatasetService.decodeCatalog(from: Data(Self.minimalJSON.utf8))
        let exercise = try #require(exercises.first)

        #expect(exercise.equipmentSummary == "Bodyweight")
        #expect(exercise.thumbnailURL == nil)
        #expect(exercise.animationURL == nil)
        #expect(exercise.imageURLs.isEmpty)
        #expect(exercise.instructions == nil)
        #expect(exercise.category == "Waist")
    }

    private static let benchPressJSON = """
    [
      {
        "id": "0025",
        "name": "barbell bench press",
        "category": "chest",
        "body_part": "chest",
        "equipment": "barbell",
        "instructions": {
          "en": "Unrack, lower, and press."
        },
        "instruction_steps": {
          "en": [
            "Unrack the bar over your chest.",
            "Lower the bar with control.",
            "Press to lockout."
          ]
        },
        "muscle_group": "chest",
        "secondary_muscles": ["triceps", "shoulders"],
        "target": "pectorals",
        "image": "images/0025-EIeI8Vf.jpg",
        "gif_url": "videos/0025-EIeI8Vf.gif",
        "created_at": "2026-03-18T12:31:32.854798+00:00"
      }
    ]
    """

    private static let pullJSON = """
    [
      {
        "id": "0652",
        "name": "pull-up",
        "category": "back",
        "body_part": "back",
        "equipment": "body weight",
        "instructions": {},
        "instruction_steps": {},
        "muscle_group": "upper back",
        "secondary_muscles": ["lower back", "biceps", "forearms"],
        "target": "lats",
        "image": "images/0652-lBDjFxJ.jpg",
        "gif_url": "videos/0652-lBDjFxJ.gif",
        "created_at": "2026-03-18T12:31:32.854798+00:00"
      }
    ]
    """

    private static let minimalJSON = """
    [
      {
        "id": "0001",
        "name": "3/4 sit-up",
        "category": "waist",
        "body_part": "waist",
        "secondary_muscles": [],
        "target": "abs"
      }
    ]
    """
}
