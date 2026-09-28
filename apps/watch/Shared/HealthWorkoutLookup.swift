import Foundation
import HealthKit
import WorkoutCore

enum HealthWorkoutLookup {
    static func find(store: HKHealthStore, sessionID: String, sourceBundleIDs: Set<String>) async throws -> HKWorkout? {
        guard UUID(uuidString: sessionID) != nil else { throw WorkoutError("Неверный UUID тренировки.") }
        let matches: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: ["traininglog.\(sessionID)"])
            // Do not limit to the first result before filtering its source. An unrelated
            // app's matching metadata must not hide or impersonate our own workout.
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let own = (samples as? [HKWorkout] ?? []).filter { sourceBundleIDs.contains($0.sourceRevision.source.bundleIdentifier) }
                continuation.resume(returning: own)
            }
            store.execute(query)
        }
        guard matches.count <= 1 else { throw WorkoutError("Найдено несколько записей TrainingLog для одной тренировки. Автоматический выбор остановлен; проверьте Apple Health.") }
        return matches.first
    }
}
