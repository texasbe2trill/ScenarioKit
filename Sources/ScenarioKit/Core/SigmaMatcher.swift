import Foundation
import Yams

struct SigmaRule {
    let id: String
    let title: String
    let description: String
    let condition: String
    let clauses: [String: SigmaClause]
}

struct SigmaClause {
    let fields: [String: [String]] // field -> patterns (may include wildcards)
}

enum SigmaMatcher {
    nonisolated(unsafe) static let shared: SigmaEngine? = {
        guard let rules = SigmaLoader.loadBundledRules() else { return nil }
        return SigmaEngine(rules: rules)
    }()
}

final class SigmaEngine {
    private let rules: [SigmaRule]
    private let ruleLookup: [String: SigmaRule]

    init(rules: [SigmaRule]) {
        self.rules = rules
        self.ruleLookup = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
    }

    func match(events: [YAMLValue]) -> [(event: YAMLValue, matches: [String])] {
        return events.compactMap { event in
            let fields = flatten(event: event)
            let ids = rules.compactMap { rule in
                rule.matches(fields: fields) ? rule.id : nil
            }
            if ids.isEmpty { return nil }
            return (event, ids)
        }
    }

    func rules(for ids: Set<String>) -> [SigmaRule] {
        ids.compactMap { ruleLookup[$0] }
    }
}

private enum SigmaLoader {
    static func loadBundledRules() -> [SigmaRule]? {
        let url: URL?
        if let direct = Bundle.module.url(forResource: "sigma-macos-rules", withExtension: "yml") {
            url = direct
        } else if let sub = Bundle.module.url(forResource: "sigma-macos-rules", withExtension: "yml", subdirectory: "Sigma/macos") {
            url = sub
        } else if let root = Bundle.module.resourceURL?.appendingPathComponent("Sigma/macos/sigma-macos-rules.yml") {
            url = root
        } else {
            url = nil
        }

        guard let resolvedURL = url else {
            fputs("⚠️  sigma: rules bundle not found; skipping Sigma matching.\n", stderr)
            return nil
        }
        do {
            let text = try String(contentsOf: resolvedURL)
            let docs = try Yams.load_all(yaml: text)
            var rules: [SigmaRule] = []
            for doc in docs {
                if let map = doc as? [String: Any], let rule = decodeRule(map: map) {
                    rules.append(rule)
                }
            }
            if rules.isEmpty {
                fputs("⚠️  sigma: loaded bundle but found zero rules.\n", stderr)
            }
            return rules
        } catch {
            fputs("⚠️  sigma: failed to load rules: \(error.localizedDescription)\n", stderr)
            return nil
        }
    }

    private static func decodeRule(map: [String: Any]) -> SigmaRule? {
        guard let id = map["id"] as? String ?? map["rule_id"] as? String,
              let title = map["title"] as? String,
              let description = map["description"] as? String,
              let detection = map["detection"] as? [String: Any],
              let condition = detection["condition"] as? String else { return nil }

        var clauses: [String: SigmaClause] = [:]
        for (key, value) in detection {
            if key == "condition" { continue }
            if let clauseMap = value as? [String: Any] {
                clauses[key] = SigmaClause(fields: decodeFields(map: clauseMap))
            }
        }

        return SigmaRule(id: id, title: title, description: description, condition: condition, clauses: clauses)
    }

    private static func decodeFields(map: [String: Any]) -> [String: [String]] {
        var fields: [String: [String]] = [:]
        for (rawKey, rawVal) in map {
            let (field, modifier) = splitField(rawKey)
            let patterns: [String]
            if let arr = rawVal as? [Any] {
                patterns = arr.compactMap { toPattern($0, modifier: modifier) }
            } else {
                patterns = toPattern(rawVal, modifier: modifier).map { [$0] } ?? []
            }
            if !patterns.isEmpty {
                fields[field, default: []].append(contentsOf: patterns)
            }
        }
        return fields
    }

    private static func toPattern(_ value: Any, modifier: FieldModifier) -> String? {
        switch value {
        case let s as String:
            switch modifier {
            case .contains: return "*\(s)*"
            case .startswith: return "\(s)*"
            case .endswith: return "*\(s)"
            case .none: return s
            }
        case let b as Bool:
            return b ? "true" : "false"
        case let i as Int:
            return String(i)
        case let d as Double:
            return String(d)
        default:
            return nil
        }
    }

    private enum FieldModifier { case contains, startswith, endswith, none }

    private static func splitField(_ raw: String) -> (String, FieldModifier) {
        if raw.contains("|contains") { return (raw.replacingOccurrences(of: "|contains", with: ""), .contains) }
        if raw.contains("|startswith") { return (raw.replacingOccurrences(of: "|startswith", with: ""), .startswith) }
        if raw.contains("|endswith") { return (raw.replacingOccurrences(of: "|endswith", with: ""), .endswith) }
        return (raw, .none)
    }
}

private extension SigmaRule {
    func matches(fields: [String: String]) -> Bool {
        let tokens = condition.split(separator: " ")
        guard !tokens.isEmpty else { return false }
        var result: Bool?
        var pendingOp: String?

        func clauseResult(name: String) -> Bool {
            guard let clause = clauses[String(name)] else { return false }
            return clause.matches(fields: fields)
        }

        for token in tokens {
            if token.lowercased() == "and" || token.lowercased() == "or" {
                pendingOp = String(token).lowercased()
                continue
            }
            let current = clauseResult(name: String(token))
            if let existing = result, let op = pendingOp {
                if op == "and" {
                    result = existing && current
                } else {
                    result = existing || current
                }
                pendingOp = nil
            } else {
                result = current
            }
        }
        return result ?? false
    }
}

private extension SigmaClause {
    func matches(fields: [String: String]) -> Bool {
        for (field, patterns) in self.fields {
            guard let value = fields[field.lowercased()] else { return false }
            let matched = patterns.contains { pattern in
                wildcardMatch(value: value, pattern: pattern.lowercased())
            }
            if !matched { return false }
        }
        return true
    }
}

private func flatten(event: YAMLValue) -> [String: String] {
    var out: [String: String] = [:]
    guard case .object(let dict) = event else { return out }
    for (k, v) in dict {
        if let s = stringify(v) {
            out[k.lowercased()] = s.lowercased()
        }
    }
    return out
}

private func stringify(_ value: YAMLValue) -> String? {
    switch value {
    case .string(let s): return s
    case .int(let i): return String(i)
    case .double(let d): return String(d)
    case .bool(let b): return b ? "true" : "false"
    case .null: return nil
    case .array(let arr):
        return arr.compactMap { stringify($0) }.joined(separator: " ")
    case .object(let dict):
        return dict.values.compactMap { stringify($0) }.joined(separator: " ")
    }
}

private func wildcardMatch(value: String, pattern: String) -> Bool {
    // convert simple * wildcard to regex
    let escaped = NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*")
    let regex = try? NSRegularExpression(pattern: "^" + escaped + "$", options: [.caseInsensitive])
    let range = NSRange(location: 0, length: value.utf16.count)
    return regex?.firstMatch(in: value, options: [], range: range) != nil
}
