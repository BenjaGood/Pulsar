//
//  NutritionMealCategoryDropDelegate.swift
//  Pulsar
//

import SwiftUI

struct NutritionMealCategoryDropDelegate: DropDelegate {
    var destinationCategory: PulsarMealCategory
    var categories: [PulsarMealCategory]
    @Binding var draggingCategoryID: UUID?
    var onMove: (IndexSet, Int) -> Void
    var reduceMotion: Bool

    func dropEntered(info: DropInfo) {
        guard let draggingCategoryID,
              draggingCategoryID != destinationCategory.id,
              let sourceIndex = categories.firstIndex(where: { $0.id == draggingCategoryID }),
              let destinationIndex = categories.firstIndex(where: { $0.id == destinationCategory.id }) else {
            return
        }

        withAnimation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.38, dampingFraction: 0.88)
        ) {
            onMove(
                IndexSet(integer: sourceIndex),
                destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingCategoryID = nil
        return true
    }
}
