import Foundation
import OSLog

nonisolated enum FoodDatabaseTrace {
    static func finish(
        requestID: UUID,
        lookupType: String,
        normalizedInput: String,
        repositoryStage: String,
        endpoint: String,
        httpStatus: Int?,
        resultCount: Int?,
        startedAt: Date,
        error: FoodCommunityServiceError?
    ) {
#if DEBUG
        let status = httpStatus.map(String.init) ?? "none"
        let count = resultCount.map(String.init) ?? "none"
        let duration = Int(Date.now.timeIntervalSince(startedAt) * 1_000)
        let mappedError = error?.diagnosticCode ?? "none"
        Logger.foodDatabase.debug(
            "request_id=\(requestID.uuidString, privacy: .public) lookup_type=\(lookupType, privacy: .public) normalized_input=\(normalizedInput, privacy: .public) repository_stage=\(repositoryStage, privacy: .public) endpoint=\(endpoint, privacy: .public) http_status=\(status, privacy: .public) result_count=\(count, privacy: .public) duration_ms=\(duration, privacy: .public) mapped_error=\(mappedError, privacy: .public)"
        )
#endif
    }
}
