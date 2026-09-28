import Foundation
import HealthKit
import Observation
import WorkoutCore

enum HealthFeature: String, CaseIterable, Identifiable {
    case sleep, restingPulse, hrv, weight, workouts
    var id: String { rawValue }
    var title: String {
        switch self { case .sleep: "Сон"; case .restingPulse: "Пульс покоя"; case .hrv: "HRV"; case .weight: "Масса тела"; case .workouts: "Измерения тренировок" }
    }
    var types: Set<HKObjectType> {
        switch self {
        case .sleep: [HKCategoryType(.sleepAnalysis)]
        case .restingPulse: [HKQuantityType(.restingHeartRate)]
        case .hrv: [HKQuantityType(.heartRateVariabilitySDNN)]
        case .weight: [HKQuantityType(.bodyMass)]
        case .workouts: [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        }
    }
}
@MainActor @Observable final class PhoneHealth {
    private let isDemo = ProcessInfo.processInfo.arguments.contains("--demo")
    var enabled = false
    var features: Set<HealthFeature> = []
    var days: [HealthDay] = []
    var feelings: [String: Int] = [:]
    var busy = false
    var status = "Данные только на устройствах"
    var updatedAt: Date?
    var cacheVersion = UUID()
    var sources: [HealthFeature: (name: String, measuredAt: Date)] = [:]
    private let store = HKHealthStore()
    private var lastRefresh = Date.distantPast
    private var refreshGeneration = UUID()
    private var feelingsReadable = false
    private var observers: [String: HKObserverQuery] = [:]
    private var refreshAgain = false
    init() {
        if !isDemo {
            enabled = UserDefaults.standard.bool(forKey: "healthAnalyticsEnabled")
            features = Set((UserDefaults.standard.stringArray(forKey: "healthFeatures") ?? []).compactMap(HealthFeature.init(rawValue:)))
        } else { status = "Демо · Apple Health не читается и не изменяется" }
    }
    var todayKey: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    var feeling: Int? { feelings[todayKey] }
    var assessment: RecoveryAssessment { RecoveryAnalytics.assess(days: days, feeling: feeling, now: .now) }
    func load() async {
        do {
            feelings = try PrivateHealthFile.read("feelings.json", as: [String: Int].self) ?? [:]
            feelingsReadable = true
        } catch { feelingsReadable = false; status = "Не удалось прочитать отметки самочувствия; файл сохранён." }
        configureObservers()
        if enabled { await refresh() }
    }
    func authorize(_ feature: HealthFeature) async {
        guard !isDemo else { status = "Демо не запрашивает разрешения Apple Health. Откройте обычный режим для измерений."; return }
        do {
            guard HKHealthStore.isHealthDataAvailable() else { throw WorkoutError("Apple Health недоступен.") }
            try await store.requestAuthorization(toShare: [], read: feature.types)
            features.insert(feature); UserDefaults.standard.set(features.map(\.rawValue), forKey: "healthFeatures")
            enabled = true; UserDefaults.standard.set(true, forKey: "healthAnalyticsEnabled")
            configureObservers()
            await refresh(force: true)
        } catch { status = "Не удалось запросить доступ. Дневник доступен без HealthKit." }
    }
    func setFeeling(_ value: Int) {
        guard feelingsReadable else { status = "Сначала восстановите чтение отметок или явно очистите локальные данные. Исходный файл не изменён."; return }
        guard (1...5).contains(value) else { return }
        do {
            var next = feelings; next[todayKey] = value
            try PrivateHealthFile.write(next, name: "feelings.json"); feelings = next
        } catch { status = "Не удалось сохранить самочувствие." }
    }
    func disable() {
        cacheVersion = UUID(); sources = [:]
        refreshGeneration = UUID()
        enabled = false
        if !isDemo { UserDefaults.standard.set(false, forKey: "healthAnalyticsEnabled") }
        refreshAgain = false
        configureObservers()
        days = []; updatedAt = nil; status = "Аналитика выключена. Apple Health не изменён."
    }
    func clearLocal() {
        do {
            try PrivateHealthFile.write([String: Int](), name: "feelings.json")
            feelingsReadable = true
            refreshGeneration = UUID()
            cacheVersion = UUID(); sources = [:]
            feelings = [:]; days = []; updatedAt = nil; lastRefresh = .distantPast
            status = "Локальные данные очищены. Apple Health не изменён."
        } catch { status = "Не удалось очистить локальные отметки." }
    }
    func refresh(force: Bool = false) async {
        guard enabled, !isDemo else { return }
        if busy { if force { refreshAgain = true }; return }
        guard force || Date().timeIntervalSince(lastRefresh) > 60 else { return }
        busy = true
        defer {
            busy = false
            if refreshAgain {
                refreshAgain = false
                Task { await self.refresh(force: true) }
            }
        }
        let generation = refreshGeneration
        do {
            let calendar = Calendar.current, now = Date()
            let start = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: now))!
            let sleep = try await featureSamples(.sleep, type: HKCategoryType(.sleepAnalysis), since: start).compactMap { $0 as? HKCategorySample }
            let pulse = try await featureSamples(.restingPulse, type: HKQuantityType(.restingHeartRate), since: start).compactMap { $0 as? HKQuantitySample }.filter(Self.fromWatch)
            let hrv = try await featureSamples(.hrv, type: HKQuantityType(.heartRateVariabilitySDNN), since: start).compactMap { $0 as? HKQuantitySample }.filter(Self.fromWatch)
            let weight = try await featureSamples(.weight, type: HKQuantityType(.bodyMass), since: start).compactMap { $0 as? HKQuantitySample }
            guard enabled, generation == refreshGeneration else { return }
            var rows: [Date: HealthDay] = [:]
            func add(_ date: Date, value: Double, key: WritableKeyPath<HealthDay, Double?>) {
                let day = calendar.startOfDay(for: date)
                var row = rows[day] ?? HealthDay(date: day, updatedAt: now)
                row[keyPath: key] = value; rows[day] = row
            }
            for (metric, key, samples, unit) in [("restingPulse", \HealthDay.restingPulse, pulse, HKUnit.count().unitDivided(by: .minute())), ("hrvMS", \HealthDay.hrvMS, hrv, HKUnit.secondUnit(with: .milli))] {
                for (date, grouped) in Dictionary(grouping: samples, by: { calendar.startOfDay(for: $0.endDate) }) {
                    if let median = RecoveryAnalytics.quantile(grouped.map { $0.quantity.doubleValue(for: unit) }, 0.5) { add(date, value: median, key: key) }
                    if rows[date]?.measurementDates == nil { rows[date]?.measurementDates = [:] }
                    rows[date]?.measurementDates?[metric] = grouped.map(\.endDate).max()
                }
            }
            for (date, grouped) in Dictionary(grouping: weight, by: { calendar.startOfDay(for: $0.endDate) }) {
                if let last = grouped.max(by: { $0.endDate < $1.endDate }) { add(date, value: last.quantity.doubleValue(for: .gramUnit(with: .kilo)), key: \.weightKG) }
            }
            let watchSleep = sleep.filter { Self.fromWatch($0) }
            let candidates = watchSleep.isEmpty ? sleep : watchSleep
            let source = candidates.max(by: { $0.endDate < $1.endDate })?.sourceRevision.source.bundleIdentifier
            let chosenSleep = candidates.filter { $0.sourceRevision.source.bundleIdentifier == source }
            var provenance: [HealthFeature: (name: String, measuredAt: Date)] = [:]
            for (feature, records) in [(HealthFeature.sleep, chosenSleep.map { $0 as HKSample }), (.restingPulse, pulse.map { $0 as HKSample }), (.hrv, hrv.map { $0 as HKSample }), (.weight, weight.map { $0 as HKSample })] {
                if let latest = records.max(by: { $0.endDate < $1.endDate }) {
                    let names = Set(records.map { $0.sourceRevision.source.name }).sorted().joined(separator: ", ")
                    provenance[feature] = (names, latest.endDate)
                }
            }
            sources = provenance
            let intervals = chosenSleep.compactMap { sample -> SleepInterval? in
                let stage: SleepInterval.Stage
                switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                case .asleepUnspecified: stage = .unspecified
                case .asleepCore: stage = .core
                case .asleepDeep: stage = .deep
                case .asleepREM: stage = .rem
                default: return nil
                }
                return SleepInterval(start: sample.startDate, end: sample.endDate, stage: stage)
            }
            for sleep in SleepAnalytics.days(intervals, calendar: calendar, now: now) {
                var row = rows[sleep.date] ?? HealthDay(date: sleep.date, updatedAt: now)
                row.sleepHours = sleep.sleepHours; row.deepHours = sleep.deepHours; row.coreHours = sleep.coreHours
                if row.measurementDates == nil { row.measurementDates = [:] }
                row.measurementDates?["sleepHours"] = sleep.measurementDates?["sleepHours"]
                row.remHours = sleep.remHours; row.wakeMinutes = sleep.wakeMinutes; rows[sleep.date] = row
            }
            days = rows.values.sorted { $0.date < $1.date }; updatedAt = now; lastRefresh = now
            status = days.isEmpty ? "Нет доступных измерений. Проверьте данные и разрешения Apple Health." : "Обновлено из Apple Health · пульс покоя и HRV: Apple Watch"
        } catch {
            guard enabled, generation == refreshGeneration else { return }
            status = "Не удалось обновить Apple Health. Показаны ранее прочитанные данные."
        }
    }
    private func configureObservers() {
        let types = enabled && !isDemo ? Set(features.flatMap { $0.types.compactMap { $0 as? HKSampleType } }) : []
        let identifiers = Set(types.map(\.identifier))
        for key in Array(observers.keys) where !identifiers.contains(key) {
            if let query = observers.removeValue(forKey: key) { store.stop(query) }
        }
        for type in types where observers[type.identifier] == nil {
            let identifier = type.identifier
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                Task { @MainActor [weak self] in
                    defer { completion() }
                    guard let self, self.enabled, self.observers[identifier] != nil else { return }
                    guard error == nil else { self.status = "Автообновление Apple Health временно недоступно. Можно обновить данные вручную."; return }
                    // Invalidate in-flight reads as well as already displayed summaries.
                    self.refreshGeneration = UUID()
                    self.cacheVersion = UUID()
                    await self.refresh(force: true)
                }
            }
            observers[identifier] = query
            store.execute(query)
        }
    }
    private static func fromWatch(_ sample: HKSample) -> Bool {
        sample.device?.model?.localizedCaseInsensitiveContains("watch") == true || sample.sourceRevision.productType?.hasPrefix("Watch") == true
    }
    private func featureSamples(_ feature: HealthFeature, type: HKSampleType, since: Date) async throws -> [HKSample] {
        guard features.contains(feature) else { return [] }
        return try await samples(type, since: since)
    }
    struct WorkoutSummary {
        let minutes: Double
        let calories: Double?
        let average: Double?
        let maximum: Double?
        let source: String
        let endedAt: Date
    }
    func workoutSummary(id: String) async throws -> WorkoutSummary? {
        guard enabled, !isDemo, features.contains(.workouts), UUID(uuidString: id) != nil else { return nil }
        let version = cacheVersion
        let workout = try await HealthWorkoutLookup.find(store: store, sessionID: id,
            sourceBundleIDs: ["ru.dcharsov.TrainingLogWatch", "ru.dcharsov.TrainingLogWatch.watchkitapp"])
        guard let workout, enabled, features.contains(.workouts) else { return nil }
        let pulse: HKStatistics? = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: HKQuantityType(.heartRate), quantitySamplePredicate: HKQuery.predicateForObjects(from: workout), options: [.discreteAverage, .discreteMax]) { _, statistics, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: statistics) }
            }
            store.execute(query)
        }
        guard enabled, features.contains(.workouts), version == cacheVersion else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return WorkoutSummary(minutes: workout.duration / 60, calories: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()), average: pulse?.averageQuantity()?.doubleValue(for: unit), maximum: pulse?.maximumQuantity()?.doubleValue(for: unit), source: workout.sourceRevision.source.name, endedAt: workout.endDate)
    }
    private func samples(_ type: HKSampleType, since: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: since, end: Date()), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }
}
