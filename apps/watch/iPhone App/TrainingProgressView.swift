import SwiftUI
import Charts
import WorkoutCore

struct TrainingProgressView: View {
    let sessions: [PhoneSession]
    private var contexts: [JSONValue] {
        var map: [TrainingProgress.Context: JSONValue] = [:]
        for row in TrainingProgress.results(sessions.map { $0.workout.json }) { map[TrainingProgress.Context(row.exercise)] = row.exercise }
        return map.values.sorted { ($0["name"].string ?? "") < ($1["name"].string ?? "") }
    }
    var body: some View {
        List {
            if contexts.isEmpty { ContentUnavailableView("Нет завершённых рабочих подходов", systemImage: "chart.xyaxis.line") }
            ForEach(contexts, id: \.progressID) { exercise in
                NavigationLink { ExerciseProgressView(sessions: sessions, exercise: exercise) } label: {
                    VStack(alignment: .leading) {
                        Text(exercise["name"].string ?? "Упражнение")
                        Text("\(exercise["equipment"].string ?? "") · \(nativeModeName(exercise["mode"].string ?? ""))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("Прогресс")
    }
}
private extension JSONValue { var progressID: String { TrainingProgress.Context(self).id } }
private struct ExerciseProgressView: View {
    let sessions: [PhoneSession]
    let exercise: JSONValue
    @State private var range = 28
    @State private var side = "all"
    @State private var weight: Int64 = -1
    private var duration: Bool { exercise["tracking"].string == "duration" }
    private var bodyweight: Bool { exercise["mode"].string == "BodyweightOnly" }
    private var metric: String { duration ? "duration" : bodyweight ? "reps" : "load" }
    private var rows: [TrainingProgress.Row] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let start = Calendar.current.date(byAdding: .day, value: -(range - 1), to: Date())!
        return TrainingProgress.results(sessions.map { $0.workout.json }, context: TrainingProgress.Context(exercise), side: side == "all" ? nil : side, from: f.string(from: start), to: f.string(from: .now))
    }
    private var loads: [Int64] { Set(rows.compactMap { $0.record["loadGrams"].integer }).sorted() }
    private var points: [TrainingProgress.Point] { TrainingProgress.points(rows, metric: metric, weight: weight < 0 ? loads.last : weight) }
    private var title: String { duration ? "Длительность, с" : bodyweight ? "Повторы" : exercise["mode"].string == "AssistedBodyweight" ? "Помощь, кг (меньше — прогресс)" : "Вес, кг" }
    var body: some View {
        List {
            Picker("Период", selection: $range) { ForEach([7, 28, 90], id: \.self) { Text("\($0) дней").tag($0) } }.pickerStyle(.segmented)
            if exercise["unilateral"].bool {
                Picker("Сторона", selection: $side) { Text("Обе").tag("all"); Text("Левая").tag("left"); Text("Правая").tag("right") }
            }
            if duration && !bodyweight {
                Picker("Вес для сравнения", selection: $weight) {
                    Text("Максимальный записанный").tag(Int64(-1))
                    ForEach(loads, id: \.self) { Text(Workout.formatWeight($0) + " кг").tag($0) }
                }
            }
            Section(title) {
                if points.isEmpty { Text("Нет сопоставимых результатов за период") }
                else {
                    Chart(points) { point in
                        PointMark(x: .value("Дата", point.date), y: .value(title, metric == "load" ? point.value / 1000 : point.value))
                    }.frame(height: 200)
                }
                Text("Лучший рабочий подход каждого занятия. Разминка, черновики и пропуски не учитываются.").font(.caption)
            }
            Section("Нагрузка за период") {
                Text("Рабочих подходов: \(rows.count)")
                if let volume = TrainingProgress.volume(rows) {
                    Text("Объём: \(volume, specifier: "%.1f") кг × повторы")
                    Text("По введённому весу в выбранном режиме. Для гантелей — вес одной гантели; режимы и оборудование не смешиваются.").font(.caption)
                }
            }
            Section("Результаты") {
                ForEach(points) { point in
                    LabeledContent(point.date, value: String(format: "%.1f", metric == "load" ? point.value / 1000 : point.value))
                }
            }
        }.navigationTitle(exercise["name"].string ?? "Прогресс").navigationBarTitleDisplayMode(.inline)
    }
}
