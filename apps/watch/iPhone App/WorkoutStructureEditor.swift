import SwiftUI
import WorkoutCore

struct WorkoutStructureEditor: View {
    let model: PhoneModel
    @State private var catalog = false
    var body: some View {
        List {
            if let row = model.diary.active {
                Section("Порядок упражнений") {
                    ForEach(row.workout.exercises, id: \.phoneID) { exercise in
                        VStack(alignment: .leading) {
                            Text(exercise["name"].string ?? "Упражнение")
                            Button(exercise["unilateral"].bool ? "Добавить разминку для обеих сторон" : "Добавить разминочный подход") {
                                Task { await model.changeStructure(.warmup(exerciseID: exercise.phoneID)) }
                            }.font(.caption).buttonStyle(.borderless)
                        }
                    }.onMove { from, to in
                        var ids = row.workout.exercises.map(\.phoneID); ids.move(fromOffsets: from, toOffset: to)
                        Task { await model.changeStructure(.reorder(ids)) }
                    }
                }.disabled(model.busy || !row.editable || model.editingSet)
                Button("Добавить упражнение из каталога") { catalog = true }.disabled(model.busy || !row.editable || model.editingSet)
                Text("Меняется только текущая тренировка. Выполненные подходы и исходная программа сохраняются. Новому упражнению выберите оборудование на экране тренировки.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Упражнения и разминка").navigationBarTitleDisplayMode(.inline)
            .toolbar { EditButton() }
            .sheet(isPresented: $catalog) { NavigationStack { NativeCatalog { guide in
                Task { await model.changeStructure(.add(guide.exercise())); catalog = false }
            } } }
    }
}
