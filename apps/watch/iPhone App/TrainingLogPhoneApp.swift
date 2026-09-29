import SwiftUI
import WorkoutCore

@main struct TrainingLogPhoneApp: App {
    @State private var model = PhoneModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            PhoneRootView(model: model).tint(.green)
                .task { await model.load(); if !model.isDemo { await model.health.load() } }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    if !model.isDemo { await model.health.refresh(force: true) }
                    while !Task.isCancelled {
                        await model.synchronize()
                        do { try await Task.sleep(for: .seconds(5)) } catch { break }
                    }
                }
        }
    }
}

private struct PhoneRootView: View {
    @Bindable var model: PhoneModel
    @State private var tab = 0
    @State private var optionalDays: Set<String> = []
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                Group {
                    if let row = model.diary.active { PhoneWorkoutView(model: model, row: row) }
                    else { programs }
                }
                .navigationTitle("Тренировка")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { if model.syncing { ProgressView() } } }
            }.id(model.diary.active?.id ?? "programs").tabItem { Label("Сегодня", systemImage: "figure.strengthtraining.traditional") }.tag(0)
            NavigationStack { programs.navigationTitle("Программы") }.tabItem { Label("Программы", systemImage: "list.bullet.rectangle") }.tag(1)
            NavigationStack { HealthDashboard(health: model.health, sessions: model.diary.sessions) }.tabItem { Label("Здоровье", systemImage: "heart") }.tag(4)
            NavigationStack {
                List {
                    NavigationLink("Календарь тренировок и отдыха") { NativeCalendar(model: model) }
                    NavigationLink("Графики прогресса") { TrainingProgressView(sessions: model.diary.sessions) }
                    if history.isEmpty { ContentUnavailableView("История появится здесь", systemImage: "clock", description: Text("Завершённые тренировки сохраняются на iPhone и в вашем дневнике.")) }
                    ForEach(history) { row in
                        NavigationLink { PhoneHistoryDetail(model: model, id: row.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(row.workout.json["name"].string ?? "Тренировка").font(.headline)
                                Text("\(row.workout.json["localDate"].string ?? "") · \(completed(row.workout)) подходов").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.navigationTitle("История")
            }.tabItem { Label("История", systemImage: "clock.arrow.circlepath") }.tag(2)
            NavigationStack { PhoneSettings(model: model).navigationTitle("Настройки") }.tabItem { Label("Настройки", systemImage: "gearshape") }.tag(3)
        }
        .alert("TrainingLog", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("Понятно") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private var history: [PhoneSession] { model.diary.sessions.filter { !$0.workout.active && $0.workout.json["deletedAt"] == .null }.sorted { ($0.workout.json["startedAt"].string ?? "") > ($1.workout.json["startedAt"].string ?? "") } }
    private var programs: some View {
        List {
            NavigationLink("Создать программу") { ProgramEditor(model: model, isNew: true, document: ProgramEditor.newProgram()) }
            LibraryDraftLinks(model: model, kind: "programs")
            if let archived = model.diary.archivedPrograms, !archived.isEmpty {
                NavigationLink("Архив программ · \(archived.count)") {
                    List(archived, id: \.phoneID) { program in
                        NavigationLink(program["name"].string ?? "Программа") {
                            ProgramEditor(model: model, isNew: false, document: program)
                        }
                    }.navigationTitle("Архив программ")
                }
            }
            if model.editorDraft != nil { NavigationLink("Восстановить незавершённый ввод") { RecoveryView(model: model) } }
            if model.hasReservation { PhoneReservationView(model: model) }
            Section {
                Label(model.isDemo ? "Демо · без отправки" : model.status, systemImage: model.isDemo ? "flask" : "checkmark.icloud")
                    .font(.footnote).foregroundStyle(.secondary)
                if !model.isDemo { Label(model.bridge.status, systemImage: "applewatch").font(.footnote) }
            }
            if model.diary.programs.isEmpty {
                ContentUnavailableView("Ваши программы", systemImage: "dumbbell", description: Text(model.loaded ? "Войдите в существующий дневник в настройках. Программы и история загрузятся без переноса вручную." : "Загружаем дневник…"))
                Button("Открыть настройки") { tab = 3 }
            }
            ForEach(model.diary.programs, id: \.phoneID) { program in
                Section(program["name"].string ?? "Программа") {
                    NavigationLink("Редактировать программу") { ProgramEditor(model: model, isNew: false, document: program) }
                    NavigationLink("Создать копию") { ProgramEditor(model: model, isNew: true, document: ProgramEditor.copy(program)) }
                    ForEach(program["days"].array.filter { $0["archivedAt"] == .null }, id: \.phoneID) { day in
                        NavigationLink {
                            List {
                                Section {
                                    if day["exercises"].array.contains(where: { $0["optionalWeekly"].bool }) {
                                        Toggle("Включить дополнительные упражнения", isOn: Binding(get: { optionalDays.contains(day.phoneID) }, set: { if $0 { optionalDays.insert(day.phoneID) } else { optionalDays.remove(day.phoneID) } }))
                                    }
                                    Button("Начать тренировку", systemImage: "play.fill") { Task {
                                        await model.start(program: program, day: day, includeOptional: optionalDays.contains(day.phoneID))
                                        if model.diary.active != nil { optionalDays.remove(day.phoneID); tab = 0 }
                                    } }
                                        .font(.headline).disabled(model.busy || model.diary.active != nil || model.hasReservation)
                                    if model.reservationsEnabled {
                                        Button("Подготовить для запуска без интернета") { Task {
                                            await model.prepareOffline(program: program, day: day, includeOptional: optionalDays.contains(day.phoneID))
                                            if model.hasReservation { optionalDays.remove(day.phoneID) }
                                        } }
                                            .disabled(model.busy || model.syncing || model.diary.active != nil || model.hasReservation)
                                    }
                                    if model.diary.active != nil { Text("Сначала завершите текущую тренировку.").font(.footnote) }
                                }
                                Section("Упражнения") {
                                    ForEach(day["exercises"].array, id: \.phoneID) { exercise in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(exercise["name"].string ?? "").font(.headline)
                                            if exercise["optionalWeekly"].bool { Text("Дополнительное · по выбору").font(.caption).foregroundStyle(.secondary) }
                                            Text("\(exercise["sets"].integer ?? 0) подхода · \(exercise["target"].string ?? "")").font(.subheadline).foregroundStyle(.secondary)
                                            if let note = exercise["sourceNote"].string, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                                        }.padding(.vertical, 4)
                                    }
                                }
                            }.navigationTitle(day["name"].string ?? "Тренировка").navigationBarTitleDisplayMode(.inline)
                        } label: {
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                let done = RecentTraining.lastDate(sessions: model.diary.sessions.map { $0.workout.json }, programID: program.phoneID, dayID: day.phoneID, now: context.date)
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(day["name"].string ?? "Тренировка").font(.headline)
                                        Text("\(day["exercises"].array.count) упражнений").font(.subheadline).foregroundStyle(.secondary)
                                        if let done {
                                            Text("Выполнено · \(done.split(separator: "-").reversed().joined(separator: "."))")
                                                .font(.caption.weight(.medium)).foregroundStyle(.green)
                                            Text("За последние 7 дней").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    if done != nil {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title2).foregroundStyle(.green)
                                            .accessibilityLabel("Выполнено за последние 7 дней")
                                    }
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }.refreshable { await model.synchronize(force: true) }
    }
}

private struct PhoneWorkoutView: View {
    let model: PhoneModel
    let row: PhoneSession
    @State private var finish = false
    @State private var forceReturn = false
    var body: some View {
        List {
            Section {
                Text(row.workout.json["name"].string ?? "Тренировка").font(.title2.bold())
                ProgressView(value: Double(completed(row.workout)), total: Double(max(1, row.workout.sequence.count))).tint(.green)
                Text("\(completed(row.workout)) / \(row.workout.sequence.count) подходов").font(.subheadline).foregroundStyle(.secondary)
                Text(row.dirty || row.pending != nil ? "Сохранено на iPhone · ожидает отправки" : model.status)
                    .font(.caption).foregroundStyle(.secondary)
                if !row.editable {
                    Label(row.conflict != nil ? "Нужна сверка версий. Локальная копия сохранена." : "Продолжайте на Apple Watch", systemImage: "applewatch").foregroundStyle(.green)
                    Text(model.status).font(.footnote).foregroundStyle(.secondary)
                    if row.control["state"].string == "offered" {
                        Button("Отменить передачу") { Task { await model.returnControl(force: false) } }.disabled(model.busy || model.syncing)
                    }
                    if ["watch", "offered"].contains(row.control["state"].string ?? "") {
                        Button("Вернуть управление принудительно", role: .destructive) { forceReturn = true }.disabled(model.busy || model.syncing)
                    }
                    if row.conflict != nil { NavigationLink("Восстановить записи") { RecoveryView(model: model) } }
                }
            }
            if let end = row.workout.restEndsAt, end > Workout.milliseconds(Date()) {
                Section("Отдых") {
                    Text(Date(timeIntervalSince1970: Double(end) / 1000), style: .timer).font(.largeTitle.monospacedDigit())
                    if row.editable {
                        HStack { Button("−30 с") { Task { await model.apply(.rest(-30)) } }; Spacer(); Button("+30 с") { Task { await model.apply(.rest(30)) } } }.buttonStyle(.bordered)
                        Button("Пропустить отдых") { Task { await model.apply(.rest(nil)) } }
                    }
                }
            }
            if model.measurementControl["sessionID"].string == row.id {
                Section("Измерение на Apple Watch") {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let pending = model.measurementPauseCommand.map { $0.expiresAt >= context.date } ?? false
                        Text(model.measurementControl["paused"].bool ? "Тренировка на паузе" : "Измерение продолжается")
                        if pending { Text("Ждём подтверждения часов…").font(.caption) }
                        else if model.measurementPauseCommand != nil { Text("Команда не подтверждена. Проверьте часы или повторите.").font(.caption).foregroundStyle(.orange) }
                        Button(model.measurementControl["paused"].bool ? "Продолжить тренировку" : "Пауза тренировки") {
                            model.requestMeasurementPause(!model.measurementControl["paused"].bool)
                        }.disabled(pending || !model.bridge.reachable || !model.measurementControl["canPause"].bool)
                        Text("Отдых между подходами не требует паузы. Состояние показано по последнему ответу часов.").font(.caption)
                    }
                }
            }
            if row.editable, let location = row.selected {
                Section("Текущий подход") {
                    PhoneSetEditor(model: model, row: row, location: location).id(location.id)
                        .disabled(model.editorDraft.map { $0.sessionID != row.id || $0.location != location } ?? false)
                }
            }
            ForEach(row.workout.exercises, id: \.phoneID) { exercise in
                Section(exercise["name"].string ?? "Упражнение") {
                    if row.editable {
                        NavigationLink("Оборудование: \(exercise["equipment"].string ?? "")") { PhoneEquipmentPicker(model: model, exercise: exercise) }
                            .disabled(model.editingSet || model.busy)
                    }
                    ForEach(Array(exercise["records"].array.enumerated()), id: \.element.phoneID) { index, record in
                        let location = SetLocation(exerciseID: exercise.phoneID, setID: record.phoneID)
                        Button {
                            if record["status"].string == "draft" { Task { await model.apply(.select(location)) } }
                            else if record["status"].string == "completed" { Task { await model.apply(.correct(location)) } }
                        } label: {
                            HStack {
                                Image(systemName: record["status"].string == "completed" ? "checkmark.circle.fill" : record["status"].string == "skipped" ? "minus.circle" : "circle")
                                Text("\(index + 1). \(record["kind"].string == "warmup" ? "Разминка · " : "")\(setSummary(record, exercise: exercise))")
                                Spacer()
                                if exercise["unilateral"].bool { Text(record["side"].string == "left" ? "Л" : "П").foregroundStyle(.secondary) }
                            }
                        }.disabled(!row.editable || model.busy || model.editingSet || record["status"].string == "skipped")
                    }
                }
            }
            if row.editable {
                if model.editingSet {
                    Text("Сначала сохраните введённые значения текущего подхода.").font(.caption).foregroundStyle(.orange)
                    NavigationLink("Восстановить незавершённый ввод") { RecoveryView(model: model) }
                }
                NavigationLink("Упражнения и разминка") { WorkoutStructureEditor(model: model) }.disabled(model.busy || model.editingSet)
                Button("Завершить тренировку", role: .destructive) { finish = true }.disabled(model.busy || model.editingSet)
            }
        }
        .confirmationDialog("Завершить? Незавершённых подходов: \(row.workout.sequence.filter { row.workout.record(at: $0)["status"].string == "draft" }.count). Они будут пропущены.", isPresented: $finish, titleVisibility: .visible) {
            Button("Завершить тренировку", role: .destructive) { Task { await model.apply(.finish) } }
        }
        .confirmationDialog("На часах могут остаться неотправленные подходы. Поздняя копия не заменит текущую тренировку — её можно будет объединить через восстановление.", isPresented: $forceReturn, titleVisibility: .visible) {
            Button("Вернуть управление", role: .destructive) { Task { await model.returnControl(force: true) } }
        }
    }
}
private struct PhoneSetEditor: View {
    let model: PhoneModel
    let row: PhoneSession
    let location: SetLocation
    @State private var weight = ""
    @State private var reps = ""
    @State private var duration = ""
    @State private var rir = ""
    @State private var note = ""
    @State private var skip = false
    @FocusState private var inputFocused: Bool
    private var exercise: JSONValue { row.workout.exercise(at: location) }
    private var suggestion: Progression.Suggestion? {
        Progression.suggest(exercise: exercise, record: row.workout.record(at: location), history: Progression.history(sessions: model.diary.sessions.map { $0.workout.json }, current: row.workout.json, exercise: exercise))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(exercise["name"].string ?? "").font(.headline)
            Text("Цель: \(exercise["target"].string ?? "")").foregroundStyle(.secondary)
            if let suggestion {
                DisclosureGroup("Подсказка из прошлых тренировок") {
                    Text("\(suggestion.weight.isEmpty ? "Без веса" : suggestion.weight + " кг") × \(suggestion.duration.isEmpty ? suggestion.reps : suggestion.duration + " сек")")
                    if let note = suggestion.note { Text(note).font(.caption) }
                    Button("Применить подсказку") {
                        weight = suggestion.weight; reps = suggestion.reps; duration = suggestion.duration
                    }.disabled(model.busy)
                    Text("Применяется только по нажатию. Текущий ввод веса и повторов будет заменён.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if exercise["unilateral"].bool { Text(row.workout.record(at: location)["side"].string == "left" ? "Левая сторона" : "Правая сторона").foregroundStyle(.orange) }
            if exercise["mode"].string != "BodyweightOnly" { LabeledContent("Вес, кг") { TextField("0", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("phoneWeight") } }
            if exercise["tracking"].string == "duration" { LabeledContent("Секунды") { TextField("0", text: $duration).keyboardType(.numberPad).multilineTextAlignment(.trailing) } }
            else { LabeledContent("Повторы") { TextField("0", text: $reps).keyboardType(.numberPad).multilineTextAlignment(.trailing).accessibilityIdentifier("phoneReps") } }
            DisclosureGroup("RIR и заметка") {
                TextField("RIR", text: $rir).keyboardType(.decimalPad)
                TextField("Заметка", text: $note, axis: .vertical)
            }
            Button { save(true) } label: { Text("Готово").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7) }
                .buttonStyle(.borderedProminent).disabled(model.busy).accessibilityIdentifier("phoneComplete")
            HStack {
                Button("Сохранить ввод") { save(false) }
                Spacer()
                Button("Пропустить") { skip = true }
            }.font(.subheadline).buttonStyle(.borderless).disabled(model.busy)
        }.padding(.vertical, 6)
        .focused($inputFocused)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Скрыть клавиатуру") { inputFocused = false }
            }
        }
        .onAppear {
            loadFields()
        }
        .onChange(of: row.workout.record(at: location)) { _, _ in if !model.editingSet { loadFields() } }
        .onChange(of: [weight, reps, duration, rir, note]) { _, _ in
            let record = row.workout.record(at: location)
            let changed = [weight, reps, duration, rir, note] != ["weight", "reps", "duration", "rir", "note"].map { record[$0].string ?? "" }
            if changed { model.stageEditor(sessionID: row.id, location: location, values: ["weight": weight, "reps": reps, "duration": duration, "rir": rir, "note": note]) }
        }
        .onDisappear { if model.editorDraft?.sessionID == row.id && model.editorDraft?.location == location { save(false) } }
        .confirmationDialog("Пропустить подход?", isPresented: $skip, titleVisibility: .visible) { Button("Пропустить", role: .destructive) { Task { await model.apply(.skip(location)) } } }
    }
    private func loadFields() {
        let record = row.workout.record(at: location)
        weight = record["weight"].string ?? ""; reps = record["reps"].string ?? ""; duration = record["duration"].string ?? ""; rir = record["rir"].string ?? ""; note = record["note"].string ?? ""
        if let draft = model.editorDraft, draft.sessionID == row.id, draft.location == location {
            weight = draft.values["weight"] ?? weight; reps = draft.values["reps"] ?? reps; duration = draft.values["duration"] ?? duration
            rir = draft.values["rir"] ?? rir; note = draft.values["note"] ?? note
        }
    }
    private func save(_ complete: Bool) {
        let values = ["weight": weight, "reps": reps, "duration": duration, "rir": rir, "note": note]
        Task { _ = await model.saveSet(location, values: values, complete: complete) }
    }
}
private struct PhoneEquipmentPicker: View {
    let model: PhoneModel
    let exercise: JSONValue
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section("Ваше оборудование") {
                ForEach(model.diary.equipment, id: \.phoneID) { equipment in
                    Button(equipment["name"].string ?? "Оборудование") { Task { await model.equipment(exerciseID: exercise.phoneID, equipment: equipment); dismiss() } }
                }
            }
            Section("Способ учёта веса") {
                ForEach(Array(modeNames.keys.sorted()), id: \.self) { mode in
                    Button(modeNames[mode]!) { Task {
                        await model.equipment(exerciseID: exercise.phoneID, equipment: .object(["id": exercise["equipmentId"], "name": exercise["equipment"], "mode": .string(mode)])); dismiss()
                    } }
                }
            }
        }.navigationTitle("Оборудование")
    }
}
struct PhoneHistoryDetail: View {
    let model: PhoneModel
    let id: String
    private var row: PhoneSession? { model.diary.sessions.first { $0.id == id } }
    var body: some View {
        List {
            if let row {
            let workout = row.workout
            Text(workout.json["localDate"].string ?? "").foregroundStyle(.secondary)
            Text(row.conflict != nil ? "Конфликт: откройте восстановление в настройках" : row.dirty ? "Изменения сохранены на iPhone · ожидают отправки" : "Сохранённая история").font(.caption)
            ForEach(workout.exercises, id: \.phoneID) { exercise in
                Section(exercise["name"].string ?? "") {
                    ForEach(exercise["records"].array, id: \.phoneID) { record in
                        if record["status"].string == "completed", workout.json["status"].string == "completed" {
                            NavigationLink { HistorySetEditor(model: model, sessionID: id, location: SetLocation(exerciseID: exercise.phoneID, setID: record.phoneID)) } label: { Text(setSummary(record, exercise: exercise)) }
                                .disabled(!row.editable || (row.base != nil && row.version == 0))
                        } else { Text(setSummary(record, exercise: exercise)) }
                    }
                }
            }
            Text("Исправление подходов не изменяет измеренные пульс и калории в Apple Health.").font(.caption).foregroundStyle(.secondary)
            if !model.isDemo { HistoryHealthView(health: model.health, sessionID: id) }
            }
        }.navigationTitle(row?.workout.json["name"].string ?? "Тренировка").navigationBarTitleDisplayMode(.inline)
            .task { await model.loadHistoryVersion(id) }
    }
}
private struct PhoneSettings: View {
    @Bindable var model: PhoneModel
    @State private var password = ""
    var body: some View {
        Form {
            Section("Дневник") {
                NavigationLink("Восстановление записей") { RecoveryView(model: model) }
                NavigationLink("Оборудование") { EquipmentLibrary(model: model) }
                if !(model.diary.documentConflicts ?? [:]).isEmpty {
                    Text("Есть конфликт изменений программы или оборудования. Локальная копия сохранена; повторная запись заблокирована.").foregroundStyle(.orange)
                }
                Text(model.status)
                if !model.signedIn && !model.isDemo {
                    SecureField("Пароль дневника", text: $password).textContentType(.password)
                    Button("Войти") { Task { await model.login(password); password = "" } }.disabled(password.isEmpty || model.syncing)
                }
                Button("Обновить данные") { Task { await model.synchronize(force: true) } }.disabled(model.syncing)
            }
            Section("Apple Watch") {
                if let measuring = model.bridge.incoming["measurementSessionID"].string,
                   model.diary.sessions.contains(where: { $0.id == measuring && !$0.workout.active }) {
                    Text("Остановка измерения на часах ожидает подтверждения связи.").foregroundStyle(.orange)
                }
                Toggle("Автоматически продолжать на часах", isOn: $model.useWatch)
                Text(model.bridge.status)
                Text("Связь через системную пару iPhone и Apple Watch. Коды и поиск устройств не нужны. Откройте TrainingLog на часах один раз после установки.").font(.footnote).foregroundStyle(.secondary)
            }
            Section { Text("Записи сохраняются на устройстве перед отправкой. Для первой загрузки истории и передачи управления нужен интернет; загруженная тренировка на часах работает офлайн.").font(.footnote).foregroundStyle(.secondary) }
        }
    }
}
extension JSONValue { var phoneID: String { self["id"].string ?? "" } }
private func completed(_ workout: Workout) -> Int { workout.sequence.filter { workout.record(at: $0)["status"].string == "completed" }.count }
private func setSummary(_ record: JSONValue, exercise: JSONValue) -> String {
    if record["status"].string == "skipped" { return "Пропущен" }
    let value = record[exercise["tracking"].string == "duration" ? "duration" : "reps"].string ?? ""
    let amount = "\(value.isEmpty ? "—" : value) \(exercise["tracking"].string == "duration" ? "с" : "повт.")"
    let weight = record["weight"].string ?? ""
    return exercise["mode"].string == "BodyweightOnly" || weight.isEmpty ? amount : "\(weight) кг × \(amount)"
}
private let modeNames = ["BarbellTotal": "Штанга · с грифом", "SmithPlatesOnly": "Смит · только блины", "PerDumbbell": "Вес одной гантели", "MachinePlatesOnly": "Блины тренажёра", "MachineStack": "Стек тренажёра", "AddedBodyweight": "Дополнительный вес", "AssistedBodyweight": "Помощь тренажёра", "BodyweightOnly": "Собственный вес"]
