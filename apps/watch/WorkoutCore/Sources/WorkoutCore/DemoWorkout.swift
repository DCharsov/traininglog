import Foundation

public enum DemoWorkout {
    public static func load() throws -> Workout {
        let data = try Data(contentsOf: Bundle.module.url(forResource: "demo-session", withExtension: "json")!)
        return try Workout(json: JSONDecoder().decode(JSONValue.self, from: data))
    }
}
