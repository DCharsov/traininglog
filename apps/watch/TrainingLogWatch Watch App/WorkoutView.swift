import SwiftUI
import WorkoutCore
import UserNotifications

struct ContentView: View {
    @State private var model = WorkoutModel()
    @State private var notifications = WorkoutNotificationDelegate()
    @Environment(\.scenePhase) private var scenePhase
    @State private var finishing = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    Color.clear.frame(height: 1).id("workoutTop")
                    if model.reservation.blocked {
                        Text("Подготовка отклонена. Запрос сохранён.").font(.caption)
                        Button("Сверить резерв с сервером") { Task { await model.reconcileReservation() } }.disabled(model.syncing)
                    }
                    if !model.reservation.blocked, model.reservation.snapshot["state"].string == "ready", model.state?.workout.id != model.reservation.snapshot["reservationId"].string {
                        Text("Готово без интернета").font(.headline)
                        Text(model.reservation.snapshot["payload"]["name"].string ?? "Следующая тренировка")
                        Button("Начать подготовленную") { Task { await model.startReserved() } }.disabled(model.busy || model.reservation.blocked)
                    }
                    if let state = model.state {
                        if !state.isDemo {
                            NavigationLink { WatchHealthView(health: model.health, state: state) } label: {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    let fresh = model.health.pulse != nil && (model.health.pulseDate.map { (0..<30).contains(context.date.timeIntervalSince($0)) } ?? false)
                                    Text(fresh ? "♥ \(Int(model.health.pulse ?? 0)) уд/мин" : "♥ — · Здоровье").foregroundStyle(.red)
                                }
                            }
                        }
                        if state.workout.active && model.editable {
                            if let end = state.workout.restEndsAt {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    let remaining = max(0, (end - Workout.milliseconds(context.date) + 999) / 1000)
                                    if remaining > 0 {
                                        Text("Отдых \(remaining / 60):\(String(format: "%02lld", remaining % 60))")
                                            .font(.title3.monospacedDigit())
                                        HStack {
                                            action("−30") { .rest(-30) }
                                            action("+30") { .rest(30) }
                                        }
                                        action("Пропустить отдых") { .rest(nil) }.font(.caption)
                                    }
                                }
                            }
                            if let location = state.selected {
                                SetCard(model: model, location: location)
                                    .id(location.setID)
                            } else {
                                Text("Все подходы записаны").font(.headline)
                            }
                            NavigationLink("Упражнения") { ExercisePicker(model: model) }
                            if let last = state.workout.sequence.filter({ state.workout.record(at: $0)["status"].string == "completed" }).max(by: {
                                (state.workout.record(at: $0)["completedAt"].string ?? "") < (state.workout.record(at: $1)["completedAt"].string ?? "")
                            }) {
                                action("Исправить последний") { .correct(last) }
                            }
                            Button("Завершить тренировку") { finishing = true }.tint(.orange)
                        } else if !state.workout.active {
                            Text("Тренировка завершена").font(.headline)
                            Text("Выполнено подходов: \(state.workout.sequence.filter { state.workout.record(at: $0)["status"].string == "completed" }.count)")
                        } else {
                            Text(model.deliveryStatus).font(.headline)
                        }
                        Text(model.deliveryStatus).font(.caption2).foregroundStyle(.green)
                        if state.isDemo { Text("Демо не отправляется в ваш дневник.").font(.caption2).foregroundStyle(.secondary) }
                    } else if model.ready {
                        Text("TrainingLog").font(.title2.bold())
                        Text("Тренировки на часах").font(.headline)
                        Text("Начните тренировку в TrainingLog на iPhone — она появится здесь автоматически.").font(.footnote)
                        Button("Открыть демо") { Task { await model.demo() } }
                    } else {
                        Text("Загрузка локальных данных…")
                    }
                    Text(model.companionBridge.status).font(.caption2).foregroundStyle(.secondary)
                    if model.connected {
                        if model.state?.isDemo == false {
                            Button("Отправить записи") { Task { await model.synchronize(force: true) } }.disabled(model.syncing)
                            if model.editable { Button("Вернуть на телефон") { Task { await model.returnToPhone() } } }
                            Button("Сохранить копию на сервере") { Task { await model.recover() } }.disabled(model.syncing)
                        }
                        Text(model.connectionStatus).font(.caption2)
                    }
                    Button("Разрешить уведомления") { Task { await model.enableNotifications() } }.font(.caption)
                    if !model.notificationStatus.isEmpty { Text(model.notificationStatus).font(.caption2) }
                    NavigationLink("Проверка установки") { InstallationProbeView() }.font(.caption)
                }.padding(.horizontal, 5)
            }
            .disabled(model.busy)
            .onChange(of: model.state?.selected?.id) { _, _ in proxy.scrollTo("workoutTop", anchor: .top) }
            .overlay { if model.busy { ProgressView() } }
            .alert("Не удалось выполнить действие", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("Понятно") { model.error = nil }
            } message: { Text(model.error ?? "") }
            .confirmationDialog("Завершить? Незавершённые подходы (\(unfinished)) будут пропущены.", isPresented: $finishing, titleVisibility: .visible) {
                Button("Завершить") { Task { _ = await model.apply(.finish) } }
                Button("Отмена", role: .cancel) { }
            }
            }
        }
        .task {
            UNUserNotificationCenter.current().delegate = notifications
            await model.load()
            await model.synchronize()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await model.companionTick()
                await model.synchronize()
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.load(); await model.synchronize() } } }
    }
    private var unfinished: Int { model.state.map { s in s.workout.sequence.filter { s.workout.record(at: $0)["status"].string == "draft" }.count } ?? 0 }
    private func action(_ title: String, _ action: @escaping () -> WorkoutAction) -> some View {
        Button(title) { let captured = action(); Task { _ = await model.apply(captured) } }
    }
}

private struct WatchHealthView: View {
    @Bindable var health: WatchHealth
    let state: WorkoutState
    @State private var confirmStart = false
    @State private var confirmClose = false
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(health.status).font(.caption)
                if !health.enabled {
                    Button("Включить Apple Health") { Task { await health.authorize(); await health.reconcile(state) } }
                    Text("Пульс и калории остаются на устройствах. Дневник работает и без доступа к здоровью.").font(.caption2)
                }
                if health.enabled, health.activeID == nil, state.workout.active {
                    Button("Начать измерения") { confirmStart = true }
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let date = health.pulseDate {
                        Text("Измерение \(Int(max(0, context.date.timeIntervalSince(date)))) с назад").font(.caption2)
                    }
                    Text("Длительность: \(Int(health.elapsed / 60)) мин")
                }
                Text("Средний пульс: \(health.average.map { String(Int($0)) } ?? "—")")
                Text("Максимальный: \(health.maximum.map { String(Int($0)) } ?? "—")")
                Text("Активные ккал: \(health.calories.map { String(Int($0)) } ?? "—")")
                if health.canPause { Button(health.paused ? "Продолжить тренировку" : "Пауза тренировки") { health.togglePause() } }
                if health.needsRecovery { Button("Восстановить измерение") { Task { await health.recover() } }.disabled(health.busy) }
                if health.canCloseUnrecoverable {
                    Button("Закрыть прерванное измерение", role: .destructive) { confirmClose = true }.disabled(health.busy)
                }
                if !state.workout.active || health.canRetryFinish {
                    Button("Повторить завершение HealthKit") { Task { await health.finish() } }.disabled(health.busy)
                }
            }
        }.navigationTitle("Apple Health")
        .confirmationDialog("Системное измерение не восстановлено. Сохранение в Apple Health не подтверждено: часть измерений могла не сохраниться. Исходный журнал останется на часах, подходы и записи Apple Health не удалятся. Повторное измерение этой же тренировки не начнётся.", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Закрыть без подтверждённой записи", role: .destructive) { Task { await health.closeUnrecoverable() } }
            Button("Оставить для восстановления", role: .cancel) { }
        }
        .confirmationDialog("Убедитесь, что другая тренировка Apple Fitness или другого приложения завершена. Часы поддерживают только одну системную тренировку.", isPresented: $confirmStart, titleVisibility: .visible) {
            Button("Другой тренировки нет — начать") { Task { await health.confirmStart(state) } }
            Button("Без измерений", role: .cancel) { }
        }
    }
}

private struct SetCard: View {
    let model: WorkoutModel
    let location: SetLocation
    @State private var skipped = false
    private var exercise: JSONValue { model.state?.workout.exercise(at: location) ?? .null }
    private var record: JSONValue { model.state?.workout.record(at: location) ?? .null }
    var body: some View {
        VStack(spacing: 8) {
            Text(exercise["name"].string ?? "Упражнение").font(.headline).multilineTextAlignment(.center)
            let records = exercise["records"].array
            Text("\((records.firstIndex { $0["id"].string == location.setID } ?? 0) + 1) / \(records.count) · цель \(exercise["target"].string ?? "")").font(.caption2).foregroundStyle(.secondary)
            if exercise["unilateral"].bool { Text(record["side"].string == "left" ? "Левая сторона" : "Правая сторона").foregroundStyle(.orange) }
            if record["kind"].string == "warmup" { Text("Разминка").font(.caption) }
            HStack {
            if exercise["mode"].string != "BodyweightOnly" { field("Вес, кг", "weight") }
            if exercise["tracking"].string == "duration" { field("Секунды", "duration") }
            else { field("Повторы", "reps") }
            }
            Button("Готово") { Task { _ = await model.apply(.complete(location)) } }
                .tint(.green).accessibilityIdentifier("completeSet")
            Text(modeLabel).font(.caption2).foregroundStyle(.secondary)
            NavigationLink("RIR / заметка") {
                ScrollView {
                    VStack(spacing: 8) {
                    field("RIR", "rir")
                    field("Заметка", "note")
                    }
                }
            }.font(.caption)
            Button("Пропустить подход") { skipped = true }.font(.caption)
        }
        .confirmationDialog("Пропустить этот подход?", isPresented: $skipped, titleVisibility: .visible) {
            Button("Пропустить") { Task { _ = await model.apply(.skip(location)) } }
        }
    }
    private func field(_ label: String, _ field: String) -> some View {
        NavigationLink {
            FieldEditor(model: model, location: location, field: field, title: label, initial: record[field].string ?? "", exercise: exercise)
        } label: {
            VStack(spacing: 2) {
                Text(label).font(.caption2)
                Text((record[field].string ?? "").isEmpty ? "—" : record[field].string!).font(.title3.monospacedDigit())
            }
        }
    }
    private var modeLabel: String {
        ["Unspecified": "Способ учёта веса не уточнён", "BarbellTotal": "Вес вместе с грифом", "SmithPlatesOnly": "Смит · только блины", "PerDumbbell": "Вес одной гантели", "MachinePlatesOnly": "Только блины тренажёра", "MachineStack": "Стек тренажёра", "AddedBodyweight": "Дополнительный вес", "AssistedBodyweight": "Помощь тренажёра", "BodyweightOnly": "Собственный вес"][exercise["mode"].string ?? ""] ?? ""
    }
}

private struct FieldEditor: View {
    let model: WorkoutModel
    let location: SetLocation
    let field: String
    let title: String
    let initial: String
    let exercise: JSONValue
    @State private var value = ""
    @State private var crown: Double = 0
    @State private var previousCrown: Double = 0
    @State private var manualStep: Int64 = 500
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
            Text(title).font(.headline)
            TextField(title, text: $value).accessibilityIdentifier("setField")
            if field != "note" {
                if field == "weight", exercise["availableGrams"].array.isEmpty, (exercise["stepGrams"].integer ?? 0) <= 0 {
                    Text("Шаг ввода, кг").font(.caption2)
                    HStack(spacing: 4) {
                        ForEach([Int64(500), 1000, 2500], id: \.self) { step in
                            Button(Workout.formatWeight(step)) { manualStep = step }
                                .tint(manualStep == step ? .green : .gray)
                                .accessibilityLabel("Шаг \(Workout.formatWeight(step)) кг")
                        }
                    }
                }
                HStack {
                Button("−") { adjust(-1) }
                    .accessibilityLabel("Уменьшить значение")
                Text(value.isEmpty ? "—" : value).font(.body.monospacedDigit())
                    .focusable()
                    .digitalCrownRotation($crown, from: -10000, through: 10000, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    .onChange(of: crown) { _, next in
                        let direction: Int64 = next > previousCrown ? 1 : -1
                        previousCrown = next
                        adjust(direction)
                    }
                Button("+") { adjust(1) }
                    .accessibilityLabel("Увеличить значение")
                }
            }
            if let error { Text(error).font(.caption2).foregroundStyle(.orange) }
            Button("Сохранить") {
                Task { if await model.apply(.field(location, field, value)) { dismiss() } }
            }.disabled(model.busy)
            }
        }
        .onAppear { value = initial }
    }
    private func adjust(_ direction: Int64) {
        do {
            if field == "weight" { value = try Workout.adjustedWeight(exercise, input: value.isEmpty ? "0" : value, direction: direction, manualStepGrams: manualStep) }
            else {
                let maximum: Int64 = field == "rir" ? 10 : field == "duration" ? 86400 : 1000
                let minimum: Int64 = field == "rir" ? 0 : 1
                value = String(min(maximum, max(minimum, (Int64(value) ?? 0) + direction)))
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct ExercisePicker: View {
    let model: WorkoutModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            if let workout = model.state?.workout {
                ForEach(workout.exercises, id: \.selfID) { e in
                    if let next = workout.sequence.first(where: { $0.exerciseID == e["id"].string && workout.record(at: $0)["status"].string == "draft" }) {
                        Button(e["name"].string ?? "Упражнение") { Task { if await model.apply(.select(next)) { dismiss() } } }
                    } else {
                        Text("✓ \(e["name"].string ?? "Упражнение")").foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("Упражнения")
    }
}

private extension JSONValue { var selfID: String { self["id"].string ?? "" } }

private struct WatchPairingView: View {
    @Bindable var model: WorkoutModel
    @State private var linking = false
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
            Text("Подключение").font(.headline)
            Text("На телефоне нажмите «Подключить часы». Здесь ничего вводить не нужно.").font(.footnote)
            Button(model.connected ? "Подключить заново" : "Подключить") { linking = true }
                .disabled(model.syncing || model.linking)
            if model.linking { ProgressView() }
            if !model.linkLabel.isEmpty { Text(model.linkLabel).font(.headline).foregroundStyle(.green) }
            if !model.linkStatus.isEmpty { Text(model.linkStatus).font(.footnote) }
            NavigationLink("Адрес сервера") {
                ScrollView {
                    VStack(spacing: 8) {
                TextField("HTTPS API", text: $model.endpoint)
                Text("Для испытаний — отдельный HTTPS-сервер. Демо никогда не отправляется.").font(.caption2)
                    }
                }
            }
            if let error = model.error { Text(error).font(.caption2).foregroundStyle(.orange) }
            }
        }
        .task(id: linking) {
            if linking { await model.linkWithoutCode(); linking = false }
        }
    }
}
