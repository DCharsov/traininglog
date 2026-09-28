import SwiftUI

struct HistoryHealthView: View {
    let health: PhoneHealth
    let sessionID: String
    @State private var summary: PhoneHealth.WorkoutSummary?
    @State private var status = "Измерения подгружаются локально из Apple Health"
    @State private var busy = false
    @State private var refreshAgain = false
    var body: some View {
        Section("Apple Health · только на устройстве") {
            if !health.enabled || !health.features.contains(.workouts) {
                Button("Подключить измерения этой тренировки") { Task { await health.authorize(.workouts); await refresh() } }
            } else if let summary {
                Text("Длительность записи: \(summary.minutes, specifier: "%.0f") мин")
                if let calories = summary.calories { Text("Активная энергия: \(calories, specifier: "%.0f") ккал") }
                if let average = summary.average { Text("Средний пульс: \(average, specifier: "%.0f") уд/мин") }
                if let maximum = summary.maximum { Text("Максимальный пульс: \(maximum, specifier: "%.0f") уд/мин") }
                Text("Источник: \(summary.source) · \(summary.endedAt.formatted())").font(.caption)
            } else { Text(status).font(.caption) }
            if health.enabled && health.features.contains(.workouts) { Button("Обновить измерения") { Task { await refresh() } }.disabled(busy) }
        }.task(id: sessionID) { await refresh() }
            .onChange(of: health.enabled) { _, enabled in if !enabled { summary = nil } }
            .onChange(of: health.cacheVersion) { _, _ in summary = nil; Task { await refresh() } }
    }
    private func refresh() async {
        guard !busy else { refreshAgain = true; return }; busy = true
        defer {
            busy = false
            if refreshAgain { refreshAgain = false; Task { await refresh() } }
        }
        summary = nil
        do {
            summary = try await health.workoutSummary(id: sessionID)
            status = "Нет доступной записи HealthKit с UUID этой тренировки. Возможно, она ещё не синхронизировалась с часов, измерение не велось или доступ ограничен."
        } catch { status = "Не удалось прочитать Apple Health. Данные дневника сохранены." }
    }
}
