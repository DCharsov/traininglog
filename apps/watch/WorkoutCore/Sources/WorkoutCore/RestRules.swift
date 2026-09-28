import Foundation

public enum RestRules {
    private struct Catalog: Decodable { let muscles: [String: [String]]; let aliases: [String: String] }
    // A checked-in snapshot of the PWA catalog; shared contract tests detect drift.
    private static let catalog = try! JSONDecoder().decode(Catalog.self, from: Data(contentsOf: Bundle.module.url(forResource: "rest-catalog", withExtension: "json")!))
    private static let muscles = Dictionary(uniqueKeysWithValues: catalog.muscles.map { (normalize($0.key), $0.value) })
    private static let overrides = [normalize("Band Pull Aparts"): Int64(60), normalize("Cable Rope Face Pulls"): 90, normalize("Lying Leg Curl - Neutral (Dorsi"): 90]
    private static func normalize(_ name: String) -> String {
        name.lowercased(with: Locale(identifier: "ru")).replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    public static func seconds(_ e: JSONValue) -> Int64 {
        if let rest = e["rest"].integer { return rest }
        let name = e["name"].string ?? ""
        let english = catalog.aliases[name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "en_US"))] ?? name
        let base: Int64
        if let override = overrides[normalize(english)] { base = override }
        else {
            let groups = e["muscle"].string.map { [$0] } ?? muscles[normalize(english)] ?? muscles[normalize(name)] ?? []
            let big: Set<String> = ["chest", "back", "quads", "hamstrings", "glutes"]
            let secondary = Array(groups.dropFirst()), compound = secondary.contains { $0 != "forearms" }
            if let primary = groups.first {
                if big.contains(primary) { base = !compound ? 120 : secondary.contains(where: big.contains) ? 180 : 150 }
                else if ["calves", "abs"].contains(primary) { base = 60 }
                else { base = compound ? 120 : 90 }
            } else { base = 90 }
        }
        let note = e["sourceNote"].string ?? ""
        let labeled = note.matches("^[A-Z][0-9]\\s*·\\s*Суперсет")
        let grouped = labeled || !(e["supersetGroup"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !grouped { return base }
        return labeled && note.dropFirst().first != "1" ? min(base, 120) : 30
    }
}
