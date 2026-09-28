import SwiftUI
import WorkoutCore

struct NativeCalendar: View {
    let model: PhoneModel
    @State private var month = Date()
    @State private var selected = Date()
    @State private var busy = false
    @State private var remove = false
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.firstWeekday = 2; return value }
    private var start: Date { calendar.dateInterval(of: .month, for: month)!.start }
    private var dayCount: Int { calendar.range(of: .day, in: .month, for: start)!.count }
    private var blanks: Int { (calendar.component(.weekday, from: start) + 5) % 7 }
    private func key(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = calendar; f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    private func sessions(_ date: Date) -> [PhoneSession] {
        model.diary.sessions.filter { !$0.workout.active && $0.workout.json["deletedAt"] == .null && $0.workout.json["localDate"].string == key(date) }
    }
    private func rest(_ date: Date) -> JSONValue? { model.diary.calendar?.first { $0["date"].string == key(date) } }
    var body: some View {
        List {
            LibraryDraftLinks(model: model, kind: "calendar")
            Section {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Предыдущий месяц")
                    Spacer(); Text(start.formatted(.dateTime.month(.wide).year())).font(.headline); Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Следующий месяц")
                }.buttonStyle(.borderless)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                    ForEach(Array(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"].enumerated()), id: \.offset) { _, day in Text(day).font(.caption).foregroundStyle(.secondary) }
                    ForEach(0..<blanks, id: \.self) { _ in Color.clear.frame(height: 40) }
                    ForEach(1...dayCount, id: \.self) { day in
                        let date = calendar.date(byAdding: .day, value: day - 1, to: start)!
                        let count = sessions(date).count
                        Button { selected = date } label: {
                            VStack(spacing: 2) {
                                Text("\(day)")
                                Image(systemName: count > 0 ? "dumbbell.fill" : rest(date) != nil ? "bed.double.fill" : "circle").font(.system(size: 8)).opacity(count > 0 || rest(date) != nil ? 1 : 0)
                            }.frame(maxWidth: .infinity, minHeight: 40)
                                .background(calendar.isDate(date, inSameDayAs: selected) ? Color.green.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.borderless).accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), тренировок: \(count)\(rest(date) != nil ? ", день отдыха" : "")")
                    }
                }
            }
            Section(selected.formatted(date: .complete, time: .omitted)) {
                ForEach(sessions(selected)) { row in
                    NavigationLink { PhoneHistoryDetail(model: model, id: row.id) } label: {
                        Text((row.workout.json["name"].string ?? "Тренировка") + (row.workout.json["status"].string == "cancelled" ? " · отменена" : ""))
                    }
                }
                if let entry = rest(selected) {
                    Text(entry["status"].string == "completed" ? "Отдых отмечен" : "Отдых запланирован")
                    Button(entry["status"].string == "completed" ? "Вернуть в план" : "Отметить отдых") { Task { await changeRest("toggle") } }
                    Button("Убрать отдых", role: .destructive) { remove = true }
                } else if sessions(selected).isEmpty {
                    Text("Нет записей").foregroundStyle(.secondary)
                    Button("Запланировать отдых") { Task { await changeRest("plan") } }
                }
            }.disabled(busy)
            Text("Отметка отдыха не создаёт тренировку и не запускает измерение Apple Health.").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Календарь").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Убрать отметку отдыха?", isPresented: $remove, titleVisibility: .visible) {
                Button("Убрать", role: .destructive) { Task { await changeRest("remove") } }
            }
    }
    private func shift(_ step: Int) { month = calendar.date(byAdding: .month, value: step, to: start)! }
    private func changeRest(_ action: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            var payload = rest(selected) ?? .object(["id": .string(UUID().uuidString), "name": .string("Отдых"), "date": .string(key(selected)), "status": .string("planned")])
            var version: Int64 = 0
            if try model.libraryDraft(kind: "calendar", id: payload["id"].string!) != nil {
                throw WorkoutError("У этой записи есть незавершённый черновик. Откройте его вверху календаря, чтобы не потерять восстановленную версию.")
            }
            if rest(selected) != nil {
                let snapshot = try await model.documentSnapshot(kind: "calendar", id: payload["id"].string!)
                version = snapshot["version"].integer ?? 0
                if !model.isDemo { payload = snapshot["payload"] }
            }
            if action == "toggle" { payload["status"] = .string(payload["status"].string == "completed" ? "planned" : "completed") }
            if action == "remove" { payload["deletedAt"] = .string(ISO8601DateFormatter().string(from: .now)) }
            _ = await model.saveDocument(kind: "calendar", payload: payload, version: version)
        } catch { model.error = error.localizedDescription }
    }
}

struct CalendarDraftEditor: View {
    let model: PhoneModel
    let draft: LibraryDraft
    @State private var document: JSONValue = .null
    @State private var ready = false
    @State private var saving = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("Название", text: text("name"))
            TextField("Дата · ГГГГ-ММ-ДД", text: text("date"))
            Picker("Отдых", selection: text("status")) {
                Text("Запланирован").tag("planned")
                Text("Отмечен").tag("completed")
            }
            if document["archivedAt"] != .null { Button("Вернуть из архива") { document["archivedAt"] = .null } }
            Text("Сохраняется исходный UUID записи. Это отметка календаря, не новая тренировка; измерения Apple Health не запускаются.").font(.caption)
            if let failure { Text(failure).foregroundStyle(.orange) }
        }.navigationTitle("Запись календаря").disabled(!ready || saving)
            .toolbar {
                Button("Сохранить") {
                    saving = true
                    Task {
                        if await model.saveDocument(kind: "calendar", payload: document, version: draft.baseVersion) { dismiss() }
                        saving = false
                    }
                }.disabled(!ready || saving)
            }
            .task {
                guard !ready else { return }
                do {
                    guard let current = try model.libraryDraft(kind: "calendar", id: draft.payload["id"].string ?? ""), current.baseVersion == draft.baseVersion else { throw WorkoutError("Черновик изменился. Откройте его заново.") }
                    document = current.payload; ready = true
                } catch { failure = error.localizedDescription }
            }
            .onChange(of: document) { _, _ in
                guard ready, !saving else { return }
                do {
                    try model.stageLibraryDraft(LibraryDraft(kind: "calendar", isNew: draft.isNew, baseVersion: draft.baseVersion, generation: draft.generation, payload: document))
                    failure = nil
                } catch { failure = "Не удалось сохранить ввод. Не закрывайте редактор: \(error.localizedDescription)" }
            }
    }
    private func text(_ key: String) -> Binding<String> {
        Binding(get: { document[key].string ?? "" }, set: { document[key] = .string($0) })
    }
}
