enum EventImport {
    static func importEvents(from anyYAML: YAMLValue, sourceName: String?) throws -> StoryboardDocument {
        let events: [YAMLValue]
        switch anyYAML {
        case .array(let arr):
            events = arr
        case .object(let dict):
            if let ev = dict["events"], case .array(let arr) = ev {
                events = arr
            } else if let cases = dict["cases"], case .array(let arr) = cases {
                events = arr
            } else {
                throw ScenarioKitError.unsupportedEventsImport
            }
        default:
            throw ScenarioKitError.unsupportedEventsImport
        }

        let timeline = events.prefix(12).enumerated().map { idx, val -> StoryboardDocument.TimelineItem in
            let headline = headlineFor(event: val) ?? "Event \(idx + 1)"
            let detail = detailFor(event: val)
            return StoryboardDocument.TimelineItem(
                time: nil,
                headline: headline,
                detail: detail,
                severity: nil
            )
        }

        let fixtures: [StoryboardDocument.Fixture] = events.enumerated().map { idx, val in
            StoryboardDocument.Fixture(
                id: String(format: "EVT-%03d", idx + 1),
                expected: [],
                result: "unknown",
                event: val
            )
        }

        let triage = StoryboardDocument.Action(
            id: "ACT-TRIAGE",
            title: "Initial triage",
            steps: [
                "Review event details and origin",
                "Collect related host/user context",
                "Check recent authentication and network activity",
                "Capture artifacts if suspicious",
                "Escalate if policy requires"
            ],
            notes: nil
        )

        return StoryboardDocument(
            version: 1,
            build: nil,
            scenario: StoryboardDocument.ScenarioMeta(
                name: sourceName ?? "Imported Events",
                description: "Auto-generated storyboard from events YAML",
                owner: nil,
                tags: nil
            ),
            severity: nil,
            signals: [],
            rules: [],
            actions: [triage],
            timeline: timeline,
            fixtures: fixtures
        )
    }

    private static func headlineFor(event: YAMLValue) -> String? {
        guard case .object(let dict) = event else { return nil }
        for key in ["message", "title", "eventName", "action", "summary"] {
            if let value = dict[key], case .string(let s) = value, !s.isEmpty { return s }
        }
        return nil
    }

    private static func detailFor(event: YAMLValue) -> String? {
        guard case .object(let dict) = event else { return nil }
        var parts: [String] = []
        if let src = dict["source"], case .string(let s) = src { parts.append("source=\(s)") }
        if let user = dict["user"], case .string(let s) = user { parts.append("user=\(s)") }
        if let ip = dict["ip"], case .string(let s) = ip { parts.append("ip=\(s)") }
        if let host = dict["host"], case .string(let s) = host { parts.append("host=\(s)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

extension EventImport {
    static func parseYAML(_ text: String) throws -> YAMLValue {
        let any = try Yams.load(yaml: text)
        return convert(any)
    }

    private static func convert(_ value: Any?) -> YAMLValue {
        guard let value else { return .null }
        switch value {
        case let s as String: return .string(s)
        case let b as Bool: return .bool(b)
        case let i as Int: return .int(i)
        case let d as Double: return .double(d)
        case let arr as [Any]:
            return .array(arr.map { convert($0) })
        case let dict as [String: Any]:
            var mapped: [String: YAMLValue] = [:]
            for key in dict.keys.sorted() {
                mapped[key] = convert(dict[key])
            }
            return .object(mapped)
        default:
            return .string(String(describing: value))
        }
    }
}
import Yams
