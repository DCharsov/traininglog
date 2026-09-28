import Foundation

/// Shared bounds of Session v2 / equipmentSchema. Missing settings permit manual input.
public enum WeightProfile {
    public static func validate(_ value: JSONValue) throws {
        if value["stepGrams"] != .null {
            guard let step = value["stepGrams"].integer, (1...2_000_000).contains(step) else {
                throw WorkoutError("Шаг должен быть от 0,001 до 2000 кг, с точностью до грамма.")
            }
        }
        if value.contains("availableGrams") {
            guard case .array(let values) = value["availableGrams"], values.count <= 200,
                  values.allSatisfy({ item in item.integer.map { (0...2_000_000).contains($0) } ?? false }) else {
                throw WorkoutError("Укажите не более 200 весов от 0 до 2000 кг, с точностью до грамма.")
            }
        }
    }
}
