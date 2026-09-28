import SwiftUI
import Charts
import WorkoutCore

struct HealthDashboard: View {
    @Bindable var health: PhoneHealth
    let sessions: [PhoneSession]
    @State private var range = 28
    @State private var clear = false
    var body: some View {
        List {
            Section {
                Text(health.status).font(.caption)
                if let updated = health.updatedAt { Text(updated, style: .relative).font(.caption) }
                if health.enabled { Button("Обновить") { Task { await health.refresh(force: true) } }.disabled(health.busy) }
                DisclosureGroup("Выбрать данные Apple Health") {
                    ForEach(HealthFeature.allCases) { feature in
                        Button("\(health.features.contains(feature) && health.enabled ? "Настроить" : "Включить"): \(feature.title)") { Task { await health.authorize(feature) } }
                    }
                    Text("Доступ подтверждается отдельно для выбранной функции. Пустой график не означает отказ: измерений может не быть.").font(.caption)
                }
            }
            Section("Самочувствие сегодня") {
                HStack {
                    ForEach(1...5, id: \.self) { value in
                        Button("\(value)") { health.setFeeling(value) }.tint(health.feeling == value ? .green : .gray)
                    }
                }.buttonStyle(.bordered)
                Text("1 — низкое, 5 — отличное. Только на этом устройстве.").font(.caption)
            }
            if health.enabled {
                Section("Экспериментальная оценка") {
                    Text(health.assessment.status).font(.headline)
                    ForEach(health.assessment.factors, id: \.self) { Text($0) }
                    if let date = health.assessment.date {
                        Text("Измерения за \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                    }
                    DisclosureGroup("Как получен статус") {
                        ForEach(health.assessment.comparisons) { comparison in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(comparison.id): \(comparison.value.formatted(.number.precision(.fractionLength(1)))) \(comparison.unit)")
                                Text("\(comparison.upperQuartile ? "Верхний" : "Нижний") квартиль вашей базы: \(comparison.threshold.formatted(.number.precision(.fractionLength(1)))) \(comparison.unit). Дней с данными: \(comparison.baselineDays) из 28.").font(.caption)
                                Text(comparison.unfavorable ? "За пределами выбранного квартиля" : "Неблагоприятный фактор не сработал").font(.caption)
                            }
                        }
                        Text("Сравнение строгое: равенство границе не считается отклонением. Текущий день не входит в базу; самочувствие учитывается за сегодня.").font(.caption)
                    }
                    Text("Личная база: 28 дней, минимум 14 дней на показатель. Это не медицинская оценка; программа не меняется автоматически.").font(.caption).foregroundStyle(.secondary)
                }
                Picker("Период", selection: $range) { ForEach([7, 28, 90], id: \.self) { Text("\($0) дней").tag($0) } }.pickerStyle(.segmented)
                graph("Сон, часов", key: \.sleepHours, feature: .sleep)
                graph("Глубокий сон, часов", key: \.deepHours, feature: .sleep)
                graph("REM, часов", key: \.remHours, feature: .sleep)
                graph("Базовый сон, часов", key: \.coreHours, feature: .sleep)
                sleepRegularity
                graph("Пульс покоя, уд/мин", key: \.restingPulse, feature: .restingPulse)
                graph("HRV, мс", key: \.hrvMS, feature: .hrv)
                graph("Масса тела, кг", key: \.weightKG, feature: .weight)
                Button("Выключить аналитику") { health.disable() }
            }
            trainingLoad
            Button("Очистить локальные данные здоровья", role: .destructive) { clear = true }
        }.navigationTitle("Восстановление")
            .task { await health.load() }
            .refreshable { await health.refresh(force: true) }
            .confirmationDialog("Очистить локальные отметки и графики? Записи Apple Health останутся.", isPresented: $clear, titleVisibility: .visible) {
                Button("Очистить", role: .destructive) { health.clearLocal() }
            }
    }
    private var sleepRegularity: some View {
        Section("Регулярность сна") {
            let values = health.days.filter { $0.date >= Date().addingTimeInterval(-Double(range) * 86400) }.compactMap(\.wakeMinutes)
            if let window = SleepAnalytics.wakeWindow(values) {
                Text("Средние 50% пробуждений: \(clock(window.startMinutes))–\(clock(window.endMinutes))").font(.subheadline)
                Text("Разброс этого интервала: \(window.spreadMinutes, specifier: "%.0f") мин. Учтён переход через полночь.").font(.caption)
            } else { Text("Нужно минимум три дня со сном") }
        }
    }
    private var completedSessions: [PhoneSession] {
        let cutoff = Date().addingTimeInterval(-Double(range) * 86400)
        let formatter = ISO8601DateFormatter()
        return sessions.filter { row in
            guard row.workout.json["status"].string == "completed", row.workout.json["deletedAt"] == .null else { return false }
            let text = row.workout.json["startedAt"].string ?? ""
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date >= cutoff }
            formatter.formatOptions = [.withInternetDateTime]
            return (formatter.date(from: text) ?? .distantPast) >= cutoff
        }
    }
    private var workingSets: Int {
        completedSessions.reduce(0) { total, row in
            total + row.workout.exercises.reduce(0) { sum, exercise in
                sum + exercise["records"].array.filter { $0["status"].string == "completed" && $0["kind"].string == "working" }.count
            }
        }
    }
    private var trainingLoad: some View {
        Section("Тренировочная нагрузка") {
            Text("Завершено тренировок: \(completedSessions.count)")
            Text("Рабочих подходов: \(workingSets)")
            Text("Длительность по дневнику: \(completedSessions.compactMap { TrainingProgress.elapsedMinutes($0.workout.json) }.reduce(0, +), specifier: "%.0f") мин")
            Text("От начала до завершения, включая отдых; это не активное время HealthKit.").font(.caption)
            NavigationLink("Нагрузка и прогресс по упражнениям") { TrainingProgressView(sessions: sessions) }
            Text("Объём разных упражнений и режимов веса не суммируется в один показатель.").font(.caption)
        }
    }
    private func clock(_ minutes: Double) -> String { String(format: "%02d:%02d", Int(minutes) / 60, Int(minutes) % 60) }
    private func graph(_ title: String, key: KeyPath<HealthDay, Double?>, feature: HealthFeature) -> some View {
        Section(title) {
            let start = Calendar.current.date(byAdding: .day, value: -range, to: Date())!
            let rows = health.days.filter { $0.date >= start && $0[keyPath: key] != nil }
            if let source = health.sources[feature] {
                Text("Источник: \(source.name) · измерение \(source.measuredAt.formatted())").font(.caption).foregroundStyle(.secondary)
            }
            if rows.isEmpty { Text("Нет доступных измерений").foregroundStyle(.secondary) }
            else {
                Chart(rows) { row in
                    PointMark(x: .value("Дата", row.date), y: .value(title, row[keyPath: key]!))
                }.frame(height: 130)
                if let last = rows.last { Text("Последнее: \(last[keyPath: key]!, specifier: "%.1f") · \(last.date.formatted(date: .abbreviated, time: .omitted))").font(.caption) }
            }
        }
    }
}
