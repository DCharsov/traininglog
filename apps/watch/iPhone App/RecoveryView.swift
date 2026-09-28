import SwiftUI
import WorkoutCore

struct RecoveryView: View {
    @Bindable var model: PhoneModel
    @State private var choices: [String: Bool] = [:]
    @State private var archiveDraft = false
    @State private var adoptGeneration = false
    @State private var restoreMissing = false
    @State private var cancelRestored = false
    var body: some View {
        List {
            if let source = model.recoveryMissingSource {
                Section("На сервере такой тренировки нет") {
                    Text(source.json["name"].string ?? "Тренировка")
                    Text("Будут сохранены прежние UUID, подходы и время. Редактирование откроется только после подтверждения сервера. Исходная копия останется в архиве.").font(.caption)
                    Button("Восстановить отсутствующую запись") { restoreMissing = true }.disabled(model.busy || model.syncing)
                }
            }
            if model.changedServerGeneration != nil {
                Section("Сервер восстановлен из копии") {
                    Text("Старые запросы не отправляются. Можно сохранить весь прежний дневник в локальном архиве и загрузить серверную версию. Объединение старых результатов выполняется отдельно, не автоматически.").font(.caption)
                    Button("Архивировать старую версию и загрузить сервер") { adoptGeneration = true }.disabled(model.busy || model.syncing)
                    Button("Отменить резерв старого поколения") { cancelRestored = true }.disabled(model.busy || model.syncing)
                }
            }
            if let draft = model.editorDraft {
                Section("Незавершённый ввод") {
                    Text("Тренировка \(draft.sessionID.prefix(8)), подход \(draft.location.setID.prefix(8))").font(.caption)
                    ForEach(["weight", "reps", "duration", "rir", "note"], id: \.self) { key in
                        let title = ["weight": "Вес", "reps": "Повторы", "duration": "Секунды", "rir": "RIR", "note": "Заметка"][key]!
                        Text("\(title): \(draft.values[key] ?? "—")")
                    }
                    if let row = model.diary.active, row.id == draft.sessionID, row.editable,
                       row.workout.record(at: draft.location)["status"].string == "draft" {
                        Button("Открыть этот подход на экране тренировки") { Task { await model.reopenEditorDraft() } }.disabled(model.busy)
                    } else { Text("Этот подход сейчас нельзя редактировать. Ввод можно сохранить в архиве, не меняя тренировку.").font(.caption) }
                    Button("Сохранить ввод в архив и продолжить") { archiveDraft = true }.disabled(model.busy)
                }
            }
            Section("Программы, оборудование и календарь") {
                let requests = (model.diary.documentWrites ?? []).filter { model.diary.documentConflicts?[$0.operationID] != nil }
                if requests.isEmpty { Text("Конфликтов документов нет") }
                ForEach(requests, id: \.operationID) { request in
                    NavigationLink(request.body["payload"]["name"].string ?? "Документ") {
                        DocumentConflictView(model: model, request: request)
                    }
                }
            }
            Section("Локальные конфликты") {
                let rows = model.diary.sessions.filter { $0.conflict != nil }
                if rows.isEmpty { Text("Конфликтов нет") }
                ForEach(rows) { row in
                    Button(row.workout.json["name"].string ?? "Тренировка") {
                        choices = [:]; Task { await model.inspectRecovery(sessionID: row.id) }
                    }
                }
            }
            Section("Сохранённые копии часов") {
                if model.recoveryCopies.isEmpty { Text("Нет загруженных копий") }
                ForEach(model.recoveryCopies, id: \.recoveryID) { copy in
                    Button("Копия \(copy["sessionId"].string?.prefix(8) ?? "")") {
                        choices = [:]
                        Task { await model.inspectRecovery(sessionID: copy["sessionId"].string ?? "", archiveID: copy["id"].string) }
                    }
                }
            }
            Section("Локальный архив · доступен без сети") {
                if model.localRecoveryCopies.isEmpty { Text("Архивных копий пока нет") }
                ForEach(model.localRecoveryCopies) { copy in
                    NavigationLink {
                        List {
                            Text(copy.date.formatted()).font(.caption)
                            if let payload = copy.payload {
                                ForEach(copy.documents.indices, id: \.self) { index in
                                    let document = copy.documents[index]
                                    NavigationLink("Восстановить в редакторе: \(document.payload["name"].string ?? document.kind) · \(index + 1)") {
                                        ArchivedDocumentEditor(model: model, document: document)
                                    }
                                }
                                ForEach(copy.workouts.indices, id: \.self) { index in
                                    let workout = copy.workouts[index]
                                    NavigationLink("Сравнить: \(workout.json["name"].string ?? "Тренировка") · версия \(index + 1)") {
                                        RecoveryView(model: model)
                                            .task { await model.inspectRecovery(sessionID: workout.id, localSource: workout) }
                                    }
                                }
                                if payload["values"] != .null {
                                    Button("Вернуть в незавершённый ввод") { model.restoreEditorArchive(payload) }.disabled(model.editorDraft != nil || model.busy)
                                    Text("Архив остаётся неизменным. Значения не применяются к тренировке автоматически.").font(.caption)
                                }
                                Text(archiveText(payload)).font(.caption.monospaced()).textSelection(.enabled)
                            } else { Text("Файл не удалось прочитать. Он не изменён и не удалён.") }
                        }.navigationTitle(copy.title)
                    } label: {
                        VStack(alignment: .leading) { Text(copy.title); Text(copy.date.formatted()).font(.caption) }
                    }
                }
            }
            if let snapshot = model.recoverySnapshot {
                Section("Сравнение по подходам") {
                    Text("Совпадающие записи не дублируются. Выберите источник для каждого расхождения. Обе исходные копии останутся сохранены.").font(.caption)
                    if snapshot["control"]["state"].string != "phone" {
                        Text("Сначала верните управление телефону на экране тренировки.").foregroundStyle(.orange)
                    }
                    ForEach(model.recoveryDifferences) { difference in
                        VStack(alignment: .leading) {
                            Text(difference.exerciseName).font(.headline)
                            Text("Подход \(difference.id.prefix(8))").font(.caption)
                            Text("Копия: \(summary(difference.local))")
                            Text("Сервер: \(summary(difference.server))")
                            HStack {
                                Button(choices[difference.id] == true ? "✓ Копия" : "Копия") { choices[difference.id] = true }
                                Button(choices[difference.id] == false ? "✓ Сервер" : "Сервер") { choices[difference.id] = false }
                            }.buttonStyle(.bordered)
                        }
                    }
                    Button("Объединить и отправить") { Task { await model.resolveRecovery(choices: choices) } }
                        .disabled(model.busy || model.syncing || snapshot["control"]["state"].string != "phone" || model.recoveryDifferences.contains { choices[$0.id] == nil })
                }
            }
        }.navigationTitle("Восстановление записей")
            .confirmationDialog("Часы могут содержать неотправленные подходы. Старый резерв будет отменён, поздние данные потребуют восстановления из отдельной копии. Продолжить?", isPresented: $cancelRestored, titleVisibility: .visible) {
                Button("Отменить старый резерв", role: .destructive) { Task { await model.cancelRestoredReservation() } }
            }
            .confirmationDialog("Восстановить эту копию на сервере? Если запись уже появилась или управление занято, изменения не перезапишут её и потребуется сверка.", isPresented: $restoreMissing, titleVisibility: .visible) {
                Button("Восстановить") { Task { await model.restoreMissingRecovery() } }
            }
            .confirmationDialog("Старый дневник и очередь останутся в локальном архиве. Текущей станет версия восстановленного сервера; неотправленные правки не применятся автоматически. Продолжить?", isPresented: $adoptGeneration, titleVisibility: .visible) {
                Button("Архивировать и загрузить") { Task { await model.adoptServerGeneration() } }
            }
            .confirmationDialog("Черновик останется в локальном архиве, но не будет применён к подходу. Продолжить?", isPresented: $archiveDraft, titleVisibility: .visible) {
                Button("Архивировать ввод") { model.archiveEditorDraft() }
            }
            .task { await model.listRecoveries() }
            .refreshable { await model.listRecoveries() }
    }
    private func summary(_ record: JSONValue) -> String {
        [record["status"].string ?? "", "\(record["weight"].string ?? "—") кг", "\(record["reps"].string ?? "—") повт.", "\(record["duration"].string ?? "—") с", "RIR \(record["rir"].string ?? "—")", record["note"].string ?? ""].joined(separator: " · ")
    }
    private func archiveText(_ payload: JSONValue) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "Копия недоступна"
    }
}
private struct DocumentConflictView: View {
    let model: PhoneModel
    let request: WatchRequest
    @State private var snapshot: JSONValue?
    @State private var generation = ""
    @State private var failure: String?
    @State private var choice: Bool?
    @State private var confirming = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Text("Выбирается документ целиком. Уже начатые тренировки не меняются. Обе исходные версии будут сохранены в локальном архиве.").font(.caption)
            if let failure { Text(failure).foregroundStyle(.orange) }
            Section("На iPhone") { Text(pretty(request.body["payload"])).font(.caption.monospaced()).textSelection(.enabled) }
            if let snapshot {
                Section("На сервере · версия \(snapshot["version"].integer ?? 0)") { Text(pretty(snapshot["payload"])).font(.caption.monospaced()).textSelection(.enabled) }
                Button("Оставить версию iPhone") { choice = true; confirming = true }
                Button("Принять серверную версию") { choice = false; confirming = true }
            }
        }.navigationTitle("Конфликт документа")
            .task { await load() }
            .refreshable { await load() }
            .confirmationDialog("Подтвердить выбранную версию? Исходники останутся в архиве.", isPresented: $confirming, titleVisibility: .visible) {
                Button("Подтвердить") {
                    guard let snapshot, let choice else { return }
                    Task { if await model.resolveDocument(request, snapshot: snapshot, generation: generation, useLocal: choice) { dismiss() } }
                }.disabled(model.busy || model.syncing)
            }
    }
    private func load() async {
        do { let result = try await model.inspectDocumentConflict(request); snapshot = result.0; generation = result.1; failure = nil }
        catch { snapshot = nil; failure = error.localizedDescription }
    }
    private func pretty(_ value: JSONValue) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "Не удалось показать документ"
    }
}
private extension JSONValue { var recoveryID: String { self["id"].string ?? "" } }

private struct ArchivedDocumentEditor: View {
    let model: PhoneModel
    let document: LocalRecoveryArchive.Document
    @State private var draft: LibraryDraft?
    @State private var loading = false
    @State private var failure: String?
    var body: some View {
        Group {
            if let draft {
                if draft.kind == "programs" { ProgramEditor(model: model, isNew: draft.isNew, document: draft.payload) }
                else if draft.kind == "calendar" { CalendarDraftEditor(model: model, draft: draft) }
                else { EquipmentEditor(model: model, isNew: draft.isNew, document: draft.payload) }
            } else {
                Form {
                    Text("Архивная версия откроется как черновик с актуальной серверной версией. Обе исходные копии сохранятся. Сервер изменится только после нажатия «Сохранить» в редакторе.")
                    if let failure { Text(failure).foregroundStyle(.orange) }
                    Button("Загрузить версию и открыть черновик") {
                        loading = true
                        Task {
                            do { draft = try await model.prepareArchivedDocument(document) }
                            catch { failure = error.localizedDescription }
                            loading = false
                        }
                    }.disabled(loading)
                }.navigationTitle("Из архива")
            }
        }
    }
}
