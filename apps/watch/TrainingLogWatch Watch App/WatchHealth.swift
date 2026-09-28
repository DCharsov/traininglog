import Foundation
import HealthKit
import Observation
import WorkoutCore

@MainActor @Observable final class WatchHealth: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = WatchHealth()
    var enabled = UserDefaults.standard.bool(forKey: "healthRecordingEnabled")
    var status = "Измерения выключены"
    var pulse: Double?
    var pulseDate: Date?
    var average: Double?
    var maximum: Double?
    var calories: Double?
    var paused = false
    func pauseBlocksSets(sessionID: String) -> Bool {
        journalReadable && journal?.blocksCompletion(of: sessionID, actualPaused: paused) == true
    }
    var busy = false
    var elapsed: TimeInterval { builder?.elapsedTime ?? 0 }
    var activeID: String? { journal?.isPending == true ? journal?.id : nil }
    private(set) var canCloseUnrecoverable = false
    private let health = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var journal: MeasurementJournal?
    private var loaded = false
    private var journalReadable = true
    private var approvedID: String?
    var onControlChange: (() -> Void)?
    var pauseSnapshot: JSONValue {
        guard let journal, journal.isPending else { return .null }
        let control = journal.pauseControl ?? MeasurementPauseState()
        var value: JSONValue = .object(["sessionID": .string(journal.id), "revision": .int(control.revision), "paused": .bool(paused), "desiredPaused": .bool(control.paused), "canPause": .bool(canPause)])
        if let id = control.lastCommand?.id { value["commandID"] = .string(id.uuidString) }
        return value
    }
    var needsRecovery: Bool { journal?.isPending == true && session == nil }
    var canRetryFinish: Bool { journal?.isPending == true && journal?.endedAt != nil }
    var canPause: Bool { !busy && journal?.endedAt == nil && (session?.state == .running || session?.state == .paused) }
    func authorize() async {
        guard !busy else { return }
        do {
            guard HKHealthStore.isHealthDataAvailable() else { throw WorkoutError("HealthKit недоступен.") }
            try await health.requestAuthorization(toShare: [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)], read: [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()])
            guard health.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { throw WorkoutError("Запись в Apple Health не разрешена. Дневник работает без измерений.") }
            enabled = true; UserDefaults.standard.set(true, forKey: "healthRecordingEnabled"); status = "Измерения включены"
        } catch { status = error.localizedDescription }
    }
    func load() async {
        guard !loaded else { return }; loaded = true
        do {
            let candidate = try PrivateHealthFile.read("watch-workout.json", as: MeasurementJournal.self)
            try candidate?.validate()
            journal = candidate
            guard let journal, journal.isPending else { return }
            await recover()
        } catch {
            journalReadable = false
            status = "Не удалось прочитать журнал HealthKit. Данные не сброшены; новое измерение заблокировано."
        }
    }
    func recover() async {
        guard !busy, journalReadable, session == nil else { return }; busy = true; canCloseUnrecoverable = false; defer { busy = false; drainDeferredFinish() }
        do {
            guard let journal, journal.isPending else { return }
            if let existing = try await existingWorkout(id: journal.id) { try markSaved(existing); return }
            let recovered: HKWorkoutSession? = try await withCheckedThrowingContinuation { continuation in
                health.recoverActiveWorkoutSession { session, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: session) }
                }
            }
            guard let recovered else { canCloseUnrecoverable = true; status = "Системное измерение недоступно для восстановления. Записи подходов сохранены; новая запись здоровья не создаётся автоматически."; return }
            session = recovered; recovered.delegate = self; builder = recovered.associatedWorkoutBuilder(); builder?.delegate = self
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: recovered.workoutConfiguration)
            paused = recovered.state == .paused; status = "Измерение восстановлено"
        } catch { status = "Восстановление HealthKit недоступно. Журнал сохранён." }
    }
    func closeUnrecoverable() async {
        guard canCloseUnrecoverable, !busy, let expectedID = activeID else { return }
        // A previous nil recovery result is not authority: re-check immediately.
        await recover()
        guard canCloseUnrecoverable, session == nil, !busy, var next = journal,
              next.id == expectedID, next.isPending else { return }
        do {
            try next.validate()
            let archive = "watch-unrecovered-\(next.id).json"
            if let original = try PrivateHealthFile.read(archive, as: MeasurementJournal.self) {
                try original.validate()
                guard original.id == next.id, original.startedAt == next.startedAt else { throw WorkoutError("Архив измерения не совпадает.") }
            } else { try PrivateHealthFile.write(next, name: archive) }
            try next.closeWithoutSave(at: Date())
            try PrivateHealthFile.write(next, name: "watch-workout.json")
            journal = next; canCloseUnrecoverable = false; approvedID = nil
            pulse = nil; pulseDate = nil; average = nil; maximum = nil; calories = nil
            status = "Попытка закрыта без подтверждения Apple Health. Журнал сохранён локально; подходы не изменены."
            onControlChange?()
        } catch { status = "Не удалось сохранить закрытие измерения. Журнал остаётся активным; повторите." }
    }
    func reconcile(_ state: WorkoutState?) async {
        guard state?.isDemo != true else { return }
        await load()
        guard journalReadable, let state, !state.isDemo else { return }
        if !state.workout.active, journal?.id == state.workout.id { await finish(); return }
        guard enabled, state.workout.active, state.sync?.controlState == "watch", state.sync?.conflict == nil, state.sync?.returning == false, !busy, session == nil else { return }
        if let journal, journal.isPending || journal.id == state.workout.id { return }
        guard approvedID == state.workout.id else { status = "Подтвердите начало измерений в разделе «Здоровье»"; return }
        await start(id: state.workout.id)
    }
    func confirmStart(_ state: WorkoutState) async {
        guard !state.isDemo, state.workout.active, state.sync?.controlState == "watch", state.sync?.conflict == nil, state.sync?.returning == false else { return }
        approvedID = state.workout.id
        await reconcile(state)
    }
    private func start(id: String) async {
        busy = true; defer { busy = false; drainDeferredFinish() }
        do {
            // Retain terminal receipts across subsequent workouts and prevent restarting
            // the same diary UUID after a delayed phone/watch snapshot or a relaunch.
            if let journal, !journal.isPending {
                try journal.validate()
                try PrivateHealthFile.write(journal, name: "watch-completed-\(journal.id).json")
            }
            if let prior = try PrivateHealthFile.read("watch-completed-\(id).json", as: MeasurementJournal.self) {
                try prior.validate()
                guard prior.id == id, !prior.isPending else { throw WorkoutError("Неоднозначный журнал прежнего измерения.") }
                status = "Измерение этой тренировки уже завершено или закрыто; повторная запись не создаётся."
                return
            }
            guard health.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { throw WorkoutError("Разрешите запись в Apple Health или продолжайте без измерений.") }
            let config = HKWorkoutConfiguration(); config.activityType = .traditionalStrengthTraining; config.locationType = .indoor
            let workout = try HKWorkoutSession(healthStore: health, configuration: config)
            let builder = workout.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: config)
            let next = MeasurementJournal(id: id, startedAt: Date())
            try PrivateHealthFile.write(next, name: "watch-workout.json"); journal = next
            self.session = workout; self.builder = builder; workout.delegate = self; builder.delegate = self
            try await builder.addMetadata([HKMetadataKeySyncIdentifier: "traininglog.\(id)", HKMetadataKeySyncVersion: 1, "TrainingLogSessionID": id])
            workout.startActivity(with: next.startedAt)
            try await builder.beginCollection(at: next.startedAt)
            pulse = nil; pulseDate = nil; calories = nil; average = nil; maximum = nil
            status = "Записываем тренировку"
        } catch {
            status = "Не удалось начать измерение. Дневник доступен. \(error.localizedDescription)"
            // Metadata/beginCollection can fail after creation of our system session.
            // Persist the finish request first; the defer drains it after busy ends.
            if journal?.id == id, journal?.isPending == true, session != nil { await finish() }
        }
    }
    func togglePause() {
        guard canPause, let journal else { return }
        let control = journal.pauseControl ?? MeasurementPauseState()
        applyPause(MeasurementPauseCommand(sessionID: journal.id, expectedRevision: control.revision, paused: !paused, now: Date()))
    }
    func applyPause(_ command: MeasurementPauseCommand) {
        guard canPause, var next = journal, next.isPending, next.endedAt == nil else { return }
        do {
            var control = next.pauseControl ?? MeasurementPauseState()
            if try control.accept(command, sessionID: next.id, now: Date()) {
                next.pauseControl = control
                try PrivateHealthFile.write(next, name: "watch-workout.json"); journal = next
            }
            applyDesiredPause()
        } catch { status = error.localizedDescription }
        onControlChange?()
    }
    private func applyDesiredPause() {
        guard let desired = journal?.pauseControl?.pendingDesiredState, journal?.endedAt == nil, let session else { return }
        if desired && session.state == .running { session.pause() }
        if !desired && session.state == .paused { session.resume() }
    }
    func finish(at date: Date = Date()) async {
        guard journalReadable, var journal, journal.isPending else { return }
        do {
            if journal.endedAt == nil { journal.requestFinish(at: date); try PrivateHealthFile.write(journal, name: "watch-workout.json"); self.journal = journal }
            switch journal.finishAction(phase: sessionPhase, collectionStarted: builder?.startDate != nil, busy: busy) {
            case .none: return
            case .persistIntent: throw WorkoutError("Завершение измерения не сохранено.")
            case .wait: status = "Завершение сохранено; ждём текущую операцию HealthKit"
            case .recover: status = "Завершение HealthKit ждёт восстановления измерения"
            case .stopActivity: session?.stopActivity(with: journal.endedAt)
            case .saveCollection: await saveFinished()
            case .endSession: session?.end()
            case .releaseUnstartedRuntime:
                session?.end()
                session = nil; builder = nil; paused = false
                status = "Сбор измерений не начался. Журнал сохранён; проверьте восстановление в разделе Apple Health."
            }
        } catch { status = "Ошибка сохранения завершения. Повторите; журнал не удалён." }
    }
    private var sessionPhase: MeasurementSessionPhase {
        guard let session else { return .absent }
        switch session.state {
        case .notStarted: return .notStarted
        case .prepared: return .prepared
        case .running: return .running
        case .paused: return .paused
        case .stopped: return .stopped
        case .ended: return .ended
        @unknown default: return .unknown
        }
    }
    private func drainDeferredFinish() {
        onControlChange?()
        if journal?.endedAt == nil { applyDesiredPause() }
        guard journal?.endedAt != nil, journal?.isPending == true, session != nil else { return }
        Task { await self.finish() }
    }
    private func saveFinished() async {
        guard !busy, var journal, journal.isPending, let builder else { return }
        busy = true; defer { busy = false }
        do {
            if let existing = try await existingWorkout(id: journal.id) { try markSaved(existing); return }
            if journal.endedAt == nil { journal.requestFinish(at: Date()); try PrivateHealthFile.write(journal, name: "watch-workout.json"); self.journal = journal }
            if !journal.collectionEnded {
                if builder.endDate == nil { try await builder.endCollection(at: journal.endedAt!) }
                try journal.endedCollection(); try PrivateHealthFile.write(journal, name: "watch-workout.json"); self.journal = journal
            }
            guard let saved = try await builder.finishWorkout() else { throw WorkoutError("Apple Health не подтвердил запись.") }
            try markSaved(saved)
        } catch { status = "Запись в Apple Health ожидает повтора. Подходы сохранены отдельно." }
    }
    private func markSaved(_ workout: HKWorkout) throws {
        guard var next = journal else { return }
        try next.saved(as: workout.uuid); try PrivateHealthFile.write(next, name: "watch-workout.json"); journal = next
        session?.end()
        session = nil; builder = nil; paused = false; status = "Сохранено в Apple Health"
        onControlChange?()
    }
    private func existingWorkout(id: String) async throws -> HKWorkout? {
        try await HealthWorkoutLookup.find(store: health, sessionID: id, sourceBundleIDs: [HKSource.default().bundleIdentifier])
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.paused = toState == .paused
            if toState == .paused || toState == .running, var next = self.journal, var control = next.pauseControl {
                control.confirm(paused: self.paused); next.pauseControl = control
                do { try PrivateHealthFile.write(next, name: "watch-workout.json"); self.journal = next }
                catch { self.status = "Не удалось сохранить подтверждение паузы. Журнал сохранён в прежнем состоянии." }
            }
            self.onControlChange?()
            if toState == .stopped || toState == .ended || self.journal?.endedAt != nil { await self.finish(at: date) }
        }
    }
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            self.status = "Измерение недоступно или прервано. Продолжайте запись подходов без измерений."
            await self.finish()
        }
    }
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            guard self.builder === workoutBuilder else { return }
            let unit = HKUnit.count().unitDivided(by: .minute())
            if collectedTypes.contains(HKQuantityType(.heartRate)), let statistics = workoutBuilder.statistics(for: HKQuantityType(.heartRate)) {
                self.pulse = statistics.mostRecentQuantity()?.doubleValue(for: unit)
                self.pulseDate = statistics.mostRecentQuantityDateInterval()?.end
                self.average = statistics.averageQuantity()?.doubleValue(for: unit); self.maximum = statistics.maximumQuantity()?.doubleValue(for: unit)
            }
            self.calories = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
    }
}
