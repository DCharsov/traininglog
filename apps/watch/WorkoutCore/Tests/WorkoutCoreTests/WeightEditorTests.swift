import Foundation
import Testing
@testable import WorkoutCore

@Test func sharedEquipmentProfileValidationMatchesWebsite() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/WorkoutCore/Resources/weight-profile-cases.json")
    let cases = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)).array
    for item in cases {
        let valid: Bool
        do { try WeightProfile.validate(item["profile"]); valid = true } catch { valid = false }
        #expect(valid == item["valid"].bool, "\(item["name"].string ?? "")")
    }
    try WeightProfile.validate(.object(["availableGrams": .array(Array(repeating: .int(1000), count: 200))]))
    #expect(throws: WorkoutError.self) { try WeightProfile.validate(.object(["availableGrams": .array(Array(repeating: .int(1000), count: 201))])) }
}

@Test func invalidEquipmentNeverEntersOutboxOrReplacesLocalProfile() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PhoneDiary(directory: directory)
    let original: JSONValue = .object(["id": .string(UUID().uuidString), "name": .string("Стек"), "mode": .string("MachineStack"), "stepGrams": .int(2500)])
    _ = try await store.importServer(.object(["equipment": .array([original]), "programs": .array([]), "sessions": .array([])]), generation: "g")
    var invalid = original; invalid["stepGrams"] = .int(0)
    await #expect(throws: WorkoutError.self) { try await store.saveDocument(kind: "equipment", payload: invalid, version: 1) }
    let state = try await PhoneDiary(directory: directory).load()
    #expect(state.equipment == [original])
    #expect(state.documentWrites?.isEmpty != false)
}

@Test func weightAdjustmentRejectsCorruptProfilesAndInvalidDirection() throws {
    #expect(throws: WorkoutError.self) { try Workout.adjustedWeight(.object(["stepGrams": .int(Int64.max)]), input: "10", direction: 1) }
    #expect(throws: WorkoutError.self) { try Workout.adjustedWeight(.object(["availableGrams": .array([.int(15000), .string("invalid")])]), input: "10", direction: 1) }
    #expect(throws: WorkoutError.self) { try Workout.adjustedWeight(.object(["stepGrams": .int(2500)]), input: "10", direction: Int64.max) }
}

@Test func watchManualStepWithoutEquipmentProfile() throws {
    let empty: JSONValue = .object([:])
    #expect(try Workout.adjustedWeight(empty, input: "0", direction: 1, manualStepGrams: 500) == "0,5")
    #expect(try Workout.adjustedWeight(empty, input: "12,5", direction: 1, manualStepGrams: 2500) == "15")
    #expect(try Workout.adjustedWeight(empty, input: "12.5", direction: -1, manualStepGrams: 1000) == "11,5")
    #expect(try Workout.adjustedWeight(empty, input: "0", direction: -1, manualStepGrams: 500) == "0")
    #expect(try Workout.adjustedWeight(empty, input: "2000", direction: 1, manualStepGrams: 500) == "2000")
}

@Test func watchManualStepDoesNotOverrideEquipment() throws {
    let stepped: JSONValue = .object(["stepGrams": .int(2500)])
    #expect(try Workout.adjustedWeight(stepped, input: "10", direction: 1, manualStepGrams: 500) == "12,5")
    let discrete: JSONValue = .object(["availableGrams": .array([.int(10000), .int(15000)]), "stepGrams": .int(2500)])
    #expect(try Workout.adjustedWeight(discrete, input: "10", direction: 1, manualStepGrams: 500) == "15")
    #expect(throws: WorkoutError.self) { try Workout.adjustedWeight(.object([:]), input: "0", direction: 1) }
}
