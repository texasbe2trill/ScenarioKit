import Foundation

struct StoryboardDocument: Decodable {
    let version: Int?
    let build: String?
    let scenario: ScenarioMeta
    let severity: Severity?
    let signals: [Signal]
    let rules: [Rule]
    let actions: [Action]
    let timeline: [TimelineItem]
    let fixtures: [Fixture]

    struct ScenarioMeta: Decodable {
        let name: String
        let description: String?
        let owner: String?
        let tags: [String]?
    }

    enum Severity: String, Decodable {
        case low, medium, high, critical

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self).lowercased()
            self = Severity(rawValue: value) ?? .medium
        }
    }

    struct Signal: Decodable {
        let id: String
        let label: String
    }

    struct Rule: Decodable {
        let id: String
        let title: String
        let severity: Severity
        let techniques: [String]?
        let explanation: String?
        let match: [RuleMatch]?
    }

    struct RuleMatch: Decodable {
        let ok: Bool?
        let text: String?
    }

    struct Action: Decodable {
        let id: String
        let title: String
        let steps: [String]
        let notes: String?
    }

    struct TimelineItem: Decodable {
        let time: String?
        let headline: String
        let detail: String?
        let severity: Severity?
    }

    struct Fixture: Decodable {
        let id: String
        let expected: [String]?
        let result: String?
        let event: YAMLValue?
    }
}

enum YAMLValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([YAMLValue])
    case object([String: YAMLValue])

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() { self = .null; return }
            if let b = try? container.decode(Bool.self) { self = .bool(b); return }
            if let i = try? container.decode(Int.self) { self = .int(i); return }
            if let d = try? container.decode(Double.self) { self = .double(d); return }
            if let s = try? container.decode(String.self) { self = .string(s); return }
        }

        if var unkeyed = try? decoder.unkeyedContainer() {
            var arr: [YAMLValue] = []
            while !unkeyed.isAtEnd {
                arr.append(try unkeyed.decode(YAMLValue.self))
            }
            self = .array(arr)
            return
        }

        if let keyed = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var dict: [String: YAMLValue] = [:]
            for key in keyed.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
                dict[key.stringValue] = try keyed.decode(YAMLValue.self, forKey: key)
            }
            self = .object(dict)
            return
        }

        self = .null
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let s):
            var c = encoder.singleValueContainer(); try c.encode(s)
        case .int(let i):
            var c = encoder.singleValueContainer(); try c.encode(i)
        case .double(let d):
            var c = encoder.singleValueContainer(); try c.encode(d)
        case .bool(let b):
            var c = encoder.singleValueContainer(); try c.encode(b)
        case .null:
            var c = encoder.singleValueContainer(); try c.encodeNil()
        case .array(let arr):
            var c = encoder.unkeyedContainer()
            for v in arr { try c.encode(v) }
        case .object(let dict):
            var c = encoder.container(keyedBy: DynamicCodingKey.self)
            for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                try c.encode(v, forKey: DynamicCodingKey(stringValue: k))
            }
        }
    }
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
