import SwiftUI
import CryptoKit
import WorkoutCore

struct ProgramEditor: View {
    let model: PhoneModel
    let isNew: Bool
    @State var document: JSONValue
    @State private var version: Int64 = 0
    @State private var ready = false
    @State private var saving = false
    @State private var failure: String?
    @State private var archive = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            if let failure { Text(failure).foregroundStyle(.orange) }
            TextField("Название программы", text: $document.text("name"))
            Section("Дни") {
                ForEach(document["days"].array.indices, id: \.self) { i in
                    NavigationLink((document["days"].array[i]["name"].string ?? "День") + (document["days"].array[i]["archivedAt"] == .null ? "" : " · архив")) {
                        DayEditor(day: $document.item("days", i), equipment: model.diary.equipment)
                    }
                    .swipeActions(edge: .leading) {
                        Button("Копировать") {
                            var days = document["days"].array
                            days.insert(ProgramEditing.copyDay(days[i]), at: i + 1)
                            document["days"] = .array(days)
                        }.tint(.blue).disabled(document["days"].array.count >= 30)
                    }
                }.onMove { from, to in var rows = document["days"].array; rows.move(fromOffsets: from, toOffset: to); document["days"] = .array(rows) }
                .onDelete { indices in var rows = document["days"].array; rows.remove(atOffsets: indices); document["days"] = .array(rows) }
                Button("Добавить день") {
                    var days = document["days"].array
                    days.append(.object(["id": .string(UUID().uuidString), "name": .string("День \(days.count + 1)"), "exercises": .array([])])); document["days"] = .array(days)
                }.disabled(document["days"].array.count >= 30)
            }
            if !isNew {
                if document["archivedAt"] != .null {
                    Text("Программа в архиве. Возврат не изменит историю и уже начатую тренировку.").font(.footnote)
                    Button("Вернуть программу из архива") { document["archivedAt"] = .null; save() }
                } else { Button("Архивировать программу", role: .destructive) { archive = true } }
            }
        }.disabled(!ready || saving)
            .navigationTitle(isNew ? "Новая программа" : "Программа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() }.disabled(!ready || saving) }; ToolbarItem(placement: .topBarLeading) { EditButton() } }
            .task {
                if ready { return }
                do {
                    if let draft = try model.libraryDraft(kind: "programs", id: document["id"].string!) {
                        document = draft.payload; version = draft.baseVersion
                    } else if !isNew {
                        let snapshot = try await model.documentSnapshot(kind: "programs", id: document["id"].string!)
                        if let number = snapshot["version"].integer { version = number }
                        if snapshot["payload"] != .null { document = snapshot["payload"] }
                    }
                    ready = true
                } catch { failure = "Для первого открытия редактора нужна связь с сервером. Изменения не потеряны." }
            }
            .onChange(of: document) { _, _ in stage() }
            .confirmationDialog("Архивировать? История и начатая тренировка сохранятся.", isPresented: $archive, titleVisibility: .visible) {
                Button("Архивировать", role: .destructive) { document["archivedAt"] = .string(Workout.timestamp(.now)); save() }
            }
    }
    private func save() {
        let currentVersion = document["version"].integer ?? 0
        guard isNew || (0..<Int64(Int32.max)).contains(currentVersion) else {
            failure = "Версия программы вне допустимого диапазона. Исходная копия сохранена."; return
        }
        saving = true
        var payload = document; payload["version"] = .int(isNew ? 1 : currentVersion + 1)
        Task { if await model.saveDocument(kind: "programs", payload: payload, version: version) { dismiss() }; saving = false }
    }
    private func stage() {
        guard ready, !saving else { return }
        do { try model.stageLibraryDraft(LibraryDraft(kind: "programs", isNew: isNew, baseVersion: version, generation: model.diary.generation, payload: document)); failure = nil }
        catch { failure = "Не удалось сохранить черновик. Не закрывайте редактор: \(error.localizedDescription)" }
    }
    static func newProgram() -> JSONValue { .object(["id": .string(UUID().uuidString), "name": .string("Новая программа"), "version": .int(1), "days": .array([])]) }
    static func copy(_ original: JSONValue) -> JSONValue {
        ProgramEditing.copyProgram(original)
    }
}

private struct DayEditor: View {
    @Binding var day: JSONValue
    let equipment: [JSONValue]
    @State private var catalog = false
    @State private var archive = false
    var body: some View {
        Form {
            TextField("Название дня", text: $day.text("name"))
            if day["archivedAt"] != .null {
                Button("Вернуть день из архива") { day = ProgramEditing.setDayArchived(day, archived: false) }
            } else { Button("Архивировать день") { archive = true } }
            Text("Изменения вступят в силу после сохранения программы. Начатые тренировки и история не меняются.").font(.caption)
            ForEach(day["exercises"].array.indices, id: \.self) { i in
                NavigationLink(day["exercises"].array[i]["name"].string ?? "Упражнение") { ExerciseEditor(exercise: $day.item("exercises", i), equipment: equipment) }
            }.onMove { from, to in var rows = day["exercises"].array; rows.move(fromOffsets: from, toOffset: to); day["exercises"] = .array(rows) }
            .onDelete { indices in var rows = day["exercises"].array; rows.remove(atOffsets: indices); day["exercises"] = .array(rows) }
            Button("Добавить упражнение") { catalog = true }.disabled(day["exercises"].array.count >= 50)
        }.navigationTitle("Тренировочный день")
            .confirmationDialog("Скрыть день из выбора тренировок? История сохранится; день можно вернуть из редактора программы.", isPresented: $archive, titleVisibility: .visible) {
                Button("Архивировать") { day = ProgramEditing.setDayArchived(day, archived: true) }
            }
            .toolbar { EditButton() }
            .sheet(isPresented: $catalog) { NavigationStack { NativeCatalog { guide in
                var exercises = day["exercises"].array; exercises.append(guide.exercise()); day["exercises"] = .array(exercises); catalog = false
            } } }
    }
}

private struct ExerciseEditor: View {
    @Binding var exercise: JSONValue
    let equipment: [JSONValue]
    var body: some View {
        Form {
            TextField("Название", text: $exercise.text("name"))
            Stepper("Подходы: \(exercise["sets"].integer ?? 3)", value: $exercise.number("sets", fallback: 3), in: 1...30)
            TextField("Цель: 8–12 или 30–60 с", text: $exercise.text("target"))
            Stepper("Отдых: \(exercise["rest"].integer ?? 90) с", value: $exercise.number("rest", fallback: 90), in: 0...1800, step: 15)
            Picker("Учёт", selection: $exercise.text("tracking", fallback: "reps")) { Text("Повторы").tag("reps"); Text("Секунды").tag("duration") }
            Toggle("По сторонам", isOn: $exercise.flag("unilateral"))
            Toggle("Дополнительное · раз в неделю", isOn: $exercise.flag("optionalWeekly"))
            if exercise["optionalWeekly"].bool { Text("Включается только по вашему выбору перед началом тренировки; расписание автоматически не меняется.").font(.caption) }
            TextField("Группа суперсета (например A)", text: $exercise.text("supersetGroup"))
            TextField("Заметка", text: $exercise.text("sourceNote"), axis: .vertical)
            Picker("Способ учёта веса", selection: $exercise.text("mode", fallback: "Unspecified")) {
                ForEach(Workout.modes, id: \.self) { Text(nativeModeName($0)).tag($0) }
            }
            Section("Оборудование") {
                Text(exercise["equipment"].string ?? "Не выбрано")
                ForEach(equipment, id: \.libraryID) { item in
                    Button(item["name"].string ?? "Оборудование") {
                        exercise["equipmentId"] = item["id"]; exercise["equipment"] = item["name"]; exercise["mode"] = item["mode"]
                        exercise["stepGrams"] = item["stepGrams"]; exercise["availableGrams"] = .array(item["availableGrams"].array)
                    }
                }
            }
        }.navigationTitle("Упражнение")
    }
}

struct NativeGuide: Decodable, Identifiable {
    let english: String
    let ru: String
    let source: String
    let cue: String
    let note: String
    let images: [String]
    var id: String { english }
    func exercise() -> JSONValue {
        let bytes = Array(SHA256.hash(data: Data(("traininglog.catalog." + english).utf8)).prefix(16))
        let variant = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], (bytes[6] & 15) | 80, bytes[7], (bytes[8] & 63) | 128, bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return .object(["id": .string(UUID().uuidString), "variantId": .string(variant.uuidString), "equipmentId": .string(UUID().uuidString), "equipment": .string("Уточните оборудование"), "name": .string(ru), "mode": .string("Unspecified"), "requiresEquipment": .bool(true), "sets": .int(3), "target": .string("8–12"), "rest": .int(90), "tracking": .string("reps"), "sourceNote": .string(cue)])
    }
}
struct NativeCatalog: View {
    let select: (NativeGuide) -> Void
    @State private var guides: [NativeGuide] = []
    @State private var search = ""
    var body: some View {
        List(guides.filter { search.isEmpty || $0.ru.localizedCaseInsensitiveContains(search) || $0.english.localizedCaseInsensitiveContains(search) }) { guide in
            NavigationLink(guide.ru) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(guide.ru).font(.headline)
                        ForEach(guide.images, id: \.self) { filename in
                            if let url = Bundle.main.url(forResource: filename, withExtension: nil), let picture = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: picture).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 220).accessibilityLabel(guide.ru)
                            } else { Text("Иллюстрация недоступна").font(.caption) }
                        }
                        Text(guide.cue); Text(guide.note).font(.caption)
                        Button("Добавить в день") { select(guide) }.buttonStyle(.borderedProminent)
                    }.padding()
                }.navigationTitle("Техника упражнения").navigationBarTitleDisplayMode(.inline)
            }
        }.navigationTitle("Каталог упражнений").searchable(text: $search)
            .task { if let url = Bundle.main.url(forResource: "exerciseGuides", withExtension: "json"), let data = try? Data(contentsOf: url) { guides = (try? JSONDecoder().decode([NativeGuide].self, from: data)) ?? [] } }
    }
}

struct EquipmentLibrary: View {
    let model: PhoneModel
    var body: some View {
        List {
            LibraryDraftLinks(model: model, kind: "equipment")
            NavigationLink("Добавить оборудование") { EquipmentEditor(model: model, isNew: true, document: .object(["id": .string(UUID().uuidString), "name": .string(""), "mode": .string("MachineStack")])) }
            ForEach(model.diary.equipment, id: \.libraryID) { item in NavigationLink(item["name"].string ?? "Оборудование") { EquipmentEditor(model: model, isNew: false, document: item) } }
        }.navigationTitle("Оборудование")
    }
}
struct EquipmentEditor: View {
    let model: PhoneModel
    let isNew: Bool
    @State var document: JSONValue
    @State private var version: Int64 = 0
    @State private var ready = false
    @State private var saving = false
    @State private var step = ""
    @State private var weights = ""
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("Название", text: $document.text("name"))
            Picker("Учёт веса", selection: $document.text("mode")) { ForEach(Workout.modes, id: \.self) { Text(nativeModeName($0)).tag($0) } }
            TextField("Шаг, кг (необязательно)", text: $step).keyboardType(.decimalPad)
            TextField("Доступные веса: 5; 7,5; 10", text: $weights)
            Text("Список весов имеет приоритет над шагом.").font(.caption)
            if let failure { Text(failure).foregroundStyle(.orange) }
        }.navigationTitle("Оборудование").disabled(!ready || saving)
            .toolbar { Button("Сохранить") { save() }.disabled(!ready || saving) }
            .task {
                if ready { return }
                do {
                    if let draft = try model.libraryDraft(kind: "equipment", id: document.libraryID) {
                        document = draft.payload; version = draft.baseVersion
                        step = draft.fields["step"] ?? ""; weights = draft.fields["weights"] ?? ""; ready = true; return
                    }
                    if !isNew { let snapshot = try await model.documentSnapshot(kind: "equipment", id: document.libraryID); version = snapshot["version"].integer ?? 0; if snapshot["payload"] != .null { document = snapshot["payload"] } }
                    step = document["stepGrams"].integer.map(Workout.formatWeight) ?? ""
                    weights = document["availableGrams"].array.compactMap(\.integer).map(Workout.formatWeight).joined(separator: "; "); ready = true
                } catch { failure = "Нужна связь с сервером для загрузки версии." }
            }
            .onChange(of: document) { _, _ in stage() }
            .onChange(of: [step, weights]) { _, _ in stage() }
    }
    private func stage() {
        guard ready, !saving else { return }
        do { try model.stageLibraryDraft(LibraryDraft(kind: "equipment", isNew: isNew, baseVersion: version, generation: model.diary.generation, payload: document, fields: ["step": step, "weights": weights])); failure = nil }
        catch { failure = "Не удалось сохранить ввод. Не закрывайте редактор: \(error.localizedDescription)" }
    }
    private func save() {
        do {
            var next = document
            next["stepGrams"] = step.isEmpty ? .null : .int(try Workout.parseWeight(step))
            guard next["stepGrams"] == .null || (next["stepGrams"].integer ?? 0) > 0 else { throw WorkoutError("Шаг должен быть больше нуля.") }
            next["availableGrams"] = .array(try weights.split(separator: ";").map { .int(try Workout.parseWeight(String($0))) })
            saving = true
            Task { if await model.saveDocument(kind: "equipment", payload: next, version: version) { dismiss() }; saving = false }
        } catch { failure = error.localizedDescription }
    }
}

struct LibraryDraftLinks: View {
    let model: PhoneModel
    let kind: String
    var body: some View {
        ForEach(model.libraryDrafts.filter { $0.kind == kind }) { draft in
            NavigationLink {
                if kind == "programs" { ProgramEditor(model: model, isNew: draft.isNew, document: draft.payload) }
                else if kind == "calendar" { CalendarDraftEditor(model: model, draft: draft) }
                else { EquipmentEditor(model: model, isNew: draft.isNew, document: draft.payload) }
            } label: { Label("Черновик: \(draft.payload["name"].string ?? "Без названия")", systemImage: "square.and.pencil") }
        }
    }
}

private extension Binding where Value == JSONValue {
    func text(_ key: String, fallback: String = "") -> Binding<String> { Binding<String>(get: { wrappedValue[key].string ?? fallback }, set: { wrappedValue[key] = .string($0) }) }
    func flag(_ key: String) -> Binding<Bool> { Binding<Bool>(get: { wrappedValue[key].bool }, set: { wrappedValue[key] = .bool($0) }) }
    func number(_ key: String, fallback: Int64) -> Binding<Int64> { Binding<Int64>(get: { wrappedValue[key].integer ?? fallback }, set: { wrappedValue[key] = .int($0) }) }
    func item(_ key: String, _ index: Int) -> Binding<JSONValue> { Binding<JSONValue>(get: { wrappedValue[key].array.indices.contains(index) ? wrappedValue[key].array[index] : .null }, set: { value in var rows = wrappedValue[key].array; guard rows.indices.contains(index) else { return }; rows[index] = value; wrappedValue[key] = .array(rows) }) }
}
private extension JSONValue { var libraryID: String { self["id"].string ?? "" } }
func nativeModeName(_ mode: String) -> String {
    ["Unspecified": "Уточнить", "BarbellTotal": "Штанга с грифом", "SmithPlatesOnly": "Смит: блины", "PerDumbbell": "Одна гантель", "MachineStack": "Стек", "MachinePlatesOnly": "Блины тренажёра", "AddedBodyweight": "Дополнительный вес", "AssistedBodyweight": "Вес помощи", "BodyweightOnly": "Собственный вес"][mode] ?? mode
}
