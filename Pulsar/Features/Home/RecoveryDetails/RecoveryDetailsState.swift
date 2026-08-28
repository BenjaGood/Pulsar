import Foundation

enum RecoveryDetailsState: Equatable {
    case loading
    case loaded
    case permissionRequired
    case noData
    case error(String)
}
