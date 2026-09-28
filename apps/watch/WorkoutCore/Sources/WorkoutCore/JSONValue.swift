import Foundation

/// Mutate known paths without discarding fields introduced by newer clients.
public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Decimal), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Decimal.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    public subscript(_ key: String) -> JSONValue {
        get { if case .object(let v) = self { return v[key] ?? .null }; return .null }
        set { if case .object(var v) = self { v[key] = newValue; self = .object(v) } }
    }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    public var bool: Bool { self == .bool(true) }
    public var integer: Int64? {
        guard case .number(let v) = self else { return nil }
        let n = NSDecimalNumber(decimal: v).int64Value
        return Decimal(n) == v ? n : nil
    }
    public func contains(_ key: String) -> Bool {
        if case .object(let v) = self { return v[key] != nil }; return false
    }
    public static func int(_ value: Int64) -> JSONValue { .number(Decimal(value)) }
}

public struct WorkoutError: LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

extension String {
    func matches(_ pattern: String) -> Bool { range(of: pattern, options: .regularExpression) != nil }
}
