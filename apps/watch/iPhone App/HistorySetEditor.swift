import SwiftUI
import WorkoutCore

struct HistorySetEditor: View {
    let model: PhoneModel
    let sessionID: String
    let location: SetLocation
    @Environment(\.dismiss) private var dismiss
    @State private var weight = ""
    @State private var reps = ""
    @State private var duration = ""
    @State private var rir = ""
    @State private var note = ""
    @State private var loaded = false
    @State private var saved = false
    @State private var readable = true
    @State private var original: JSONValue = .null
    @State private var staleDraft = false
    private var draftFile: URL { EditorDraft.file.deletingLastPathComponent().appendingPathComponent("history-\(sessionID)-\(location.setID).json") }
    private var row: PhoneSession? { model.diary.sessions.first { $0.id == sessionID } }
    var body: some View {
        Form {
            if let row {
                let exercise = row.workout.exercise(at: location)
                Text(exercise["name"].string ?? "Подход")
                if exercise["mode"].string != "BodyweightOnly" { TextField("Вес, кг", text: $weight).keyboardType(.decimalPad) }
                if exercise["tracking"].string == "duration" { TextField("Секунды", text: $duration).keyboardType(.numberPad) }
                else { TextField("Повторы", text: $reps).keyboardType(.numberPad) }
                TextField("RIR", text: $rir).keyboardType(.numberPad)
                TextField("Заметка", text: $note, axis: .vertical)
                Text("UUID и время выполнения сохраняются. Запись Apple Health не меняется.").font(.caption)
                if staleDraft {
                    Section("Запись изменилась после создания черновика") {
                        let current = row.workout.record(at: location)
                        Text("Текущая версия: вес \(current["weight"].string ?? "—"), повторы \(current["reps"].string ?? "—"), секунды \(current["duration"].string ?? "—"), RIR \(current["rir"].string ?? "—").")
                        Text(current["note"].string ?? "").font(.caption)
                        Text("В полях выше сохранён ваш черновик. Выберите, с какой версией продолжить.").font(.caption)
                        Button("Продолжить с моим черновиком") { resolveDraft(useCurrent: false) }
                        Button("Взять текущую запись") { resolveDraft(useCurrent: true) }
                    }
                }
                Button("Сохранить исправление") {
                    Task {
                        if await model.correctHistory(id: sessionID, location: location, values: ["weight": weight, "reps": reps, "duration": duration, "rir": rir, "note": note], expectedRecord: original) {
                            do { try EditorDraft.write(nil, to: draftFile); saved = true; dismiss() }
                            catch { model.error = "Исправление сохранено, но черновик не удалось очистить. Повторите сохранение." }
                        }
                    }
                }.disabled(model.busy || !row.editable || !readable || staleDraft)
            }
        }.navigationTitle("Исправить подход").navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !loaded, let row else { return }; loaded = true
                let record = row.workout.record(at: location)
                original = record
                weight = record["weight"].string ?? ""; reps = record["reps"].string ?? ""; duration = record["duration"].string ?? ""
                rir = record["rir"].string ?? ""; note = record["note"].string ?? ""
                do {
                    if let draft = try EditorDraft.read(from: draftFile) {
                        guard draft.sessionID == sessionID, draft.location == location else { throw WorkoutError("Черновик другого подхода.") }
                        original = draft.originalRecord ?? .null
                        staleDraft = draft.originalRecord != record
                        weight = draft.values["weight"] ?? weight; reps = draft.values["reps"] ?? reps; duration = draft.values["duration"] ?? duration
                        rir = draft.values["rir"] ?? rir; note = draft.values["note"] ?? note
                    }
                } catch { readable = false; model.error = "Не удалось прочитать черновик исправления. Файл сохранён; запись заблокирована." }
            }
            .onChange(of: [weight, reps, duration, rir, note]) { _, _ in
                guard loaded, !saved, readable else { return }
                do { try persistDraft() }
                catch { model.error = "Ошибка сохранения черновика. Не закрывайте редактор." }
            }
    }
    private func persistDraft() throws {
        try EditorDraft.write(EditorDraft(sessionID: sessionID, location: location, values: ["weight": weight, "reps": reps, "duration": duration, "rir": rir, "note": note], originalRecord: original), to: draftFile)
    }
    private func resolveDraft(useCurrent: Bool) {
        guard let row else { return }
        let record = row.workout.record(at: location)
        do {
            let values = useCurrent
                ? Dictionary(uniqueKeysWithValues: ["weight", "reps", "duration", "rir", "note"].map { ($0, record[$0].string ?? "") })
                : ["weight": weight, "reps": reps, "duration": duration, "rir": rir, "note": note]
            // Commit the choice before removing the conflict from the screen.
            try EditorDraft.write(EditorDraft(sessionID: sessionID, location: location, values: values, originalRecord: record), to: draftFile)
            original = record
            weight = values["weight"] ?? ""; reps = values["reps"] ?? ""; duration = values["duration"] ?? ""
            rir = values["rir"] ?? ""; note = values["note"] ?? ""
            staleDraft = false
        } catch { model.error = "Не удалось сохранить выбор версии. Исходный черновик сохранён." }
    }
}
