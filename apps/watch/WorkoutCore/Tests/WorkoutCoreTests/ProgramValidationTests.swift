import Foundation
import Testing
@testable import WorkoutCore

@Test func sharedProgramValidationMatchesWebsite() throws {
    let demo = try DemoWorkout.load()
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/WorkoutCore/Resources/program-validation-cases.json")
    let cases = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)).array
    for item in cases {
        var exercise = demo.exercises[0]
        var day: JSONValue = .object(["id": demo.json["dayId"], "name": .string("Day")])
        var program: JSONValue = .object(["id": demo.json["programId"], "name": .string("Program"), "version": .int(1)])
        let key = item["key"].string!
        if item["scope"].string == "exercise" { exercise[key] = item["value"] }
        day["exercises"] = .array([exercise])
        if item["scope"].string == "day" { day[key] = item["value"] }
        program["days"] = .array([day])
        if item["scope"].string == "program" { program[key] = item["value"] }
        let valid: Bool
        do { try ProgramValidation.validate(program); valid = true } catch { valid = false }
        #expect(valid == item["valid"].bool, "\(item["name"].string ?? "")")
    }
}

@Test func invalidProgramNeverEntersOutboxIncludingOptionalExercises() async throws {
    let demo = try DemoWorkout.load()
    var exercise = demo.exercises[0]; exercise["optionalWeekly"] = .bool(true)
    let day: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("День"), "exercises": .array([exercise])])
    let program: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("Программа"), "version": .int(1), "days": .array([day]), "futureField": .string("keep")])
    try ProgramValidation.validate(program)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory)
    _ = try await store.importServer(.object(["programs": .array([program]), "equipment": .array([]), "sessions": .array([])]), generation: "g")
    for (key, value): (String, JSONValue) in [("name", .string("")), ("equipmentId", .string("bad")), ("rest", .int(-1)), ("stepGrams", .int(0)), ("unilateral", .string("true")), ("supersetGroup", .string(String(repeating: "A", count: 51)))] {
        var invalidExercise = exercise; invalidExercise[key] = value
        var invalidDay = day; invalidDay["exercises"] = .array([invalidExercise])
        var invalid = program; invalid["days"] = .array([invalidDay])
        await #expect(throws: WorkoutError.self) { try await store.saveDocument(kind: "programs", payload: invalid, version: 1) }
    }
    let state = try await PhoneDiary(directory: directory).load()
    #expect(state.programs == [program] && state.documentWrites?.isEmpty != false)
    var duplicate = program; duplicate["days"] = .array([day, day])
    #expect(throws: WorkoutError.self) { try ProgramValidation.validate(duplicate) }
    var invalidDate = program; invalidDate["archivedAt"] = .string("tomorrow")
    #expect(throws: WorkoutError.self) { try ProgramValidation.validate(invalidDate) }
}
