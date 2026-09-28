import SwiftUI
import WorkoutCore

struct PhoneReservationView: View {
    let model: PhoneModel
    @State private var cancel = false
    @State private var reconcile = false
    var body: some View {
        Section("Следующая тренировка на часах") {
            Text(model.reservation.snapshot["payload"]["name"].string ?? "Сохраняем резерв…").font(.headline)
            Text(model.reservation.blocked ? "Нужна сверка резерва. Локальная копия сохранена." : model.reservation.startRequested ? "Команда старта сохранена · ожидаем часы" : model.reservationReady ? "Готово без интернета" : "Ожидаем подтверждения сохранения на часах")
            if model.reservation.blocked { Button("Сверить отклонённый запрос") { reconcile = true }.disabled(model.busy || model.syncing) }
            if model.reservationReady {
                Button("Начать на часах") { Task { await model.startOfflineOnWatch() } }
                Text("iPhone остаётся наблюдателем. При отсутствии связи начните прямо на часах.").font(.caption)
            }
            if ["preparing", "ready"].contains(model.reservation.snapshot["state"].string ?? "") {
                Button("Принудительно отменить резерв", role: .destructive) { cancel = true }.disabled(model.busy || model.syncing)
            }
        }.confirmationDialog("Часы могли уже начать тренировку без сети. Поздние результаты сохранятся отдельно для восстановления и не заменят новую тренировку.", isPresented: $cancel, titleVisibility: .visible) {
            Button("Отменить резерв", role: .destructive) { Task { await model.cancelReservation() } }
        }
        .confirmationDialog("Сохранить отклонённый запрос в локальный архив и принять актуальное состояние резерва с сервера? Записи подходов не удаляются.", isPresented: $reconcile, titleVisibility: .visible) {
            Button("Сверить") { Task { await model.reconcileReservation() } }
        }
    }
}
