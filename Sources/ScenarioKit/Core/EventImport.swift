import Foundation
import Yams

enum EventImport {
    static func importEvents(from anyYAML: YAMLValue, sourceName: String?) throws -> StoryboardDocument {
        let events: [YAMLValue]
        switch anyYAML {
        case .array(let arr):
            events = arr
        case .object(let dict):
            if let ev = dict["events"], case .array(let arr) = ev {
                events = arr
            } else if let items = dict["items"], case .array(let arr) = items {
                events = arr
            } else {
                throw ScenarioKitError.unsupportedEventsImport
            }
        default:
            throw ScenarioKitError.unsupportedEventsImport
        }

        let tags = detectTags(from: events)
        let signals = detectSignals(from: events)

        let timeline = events.prefix(12).enumerated().map { idx, val -> StoryboardDocument.TimelineItem in
            let headline = headlineFor(event: val) ?? "Event \(idx + 1)"
            let detail = detailFor(event: val)
            let time = timeFor(event: val)
            let severity = severityFor(event: val)
            return StoryboardDocument.TimelineItem(
                time: time,
                headline: headline,
                detail: detail,
                severity: severity
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
            notes: "Capture evidence: logs, command lines, network destinations, and user context."
        )

        let actions = buildActions(tags: tags, hasHigh: timeline.contains { ($0.severity ?? .medium) == .high || ($0.severity ?? .medium) == .critical })

        let rules = generateRules(from: events, tags: tags)
        let ruleIDs = rules.map { $0.id }

        let fixturesWithExpected = fixtures.map { fixture -> StoryboardDocument.Fixture in
            let expected = matchRules(for: fixture.event, ruleIDs: ruleIDs)
            return StoryboardDocument.Fixture(
                id: fixture.id,
                expected: expected.isEmpty ? fixture.expected : expected,
                result: fixture.result,
                event: fixture.event
            )
        }

        let name = sourceName ?? deriveName(tags: tags)
        let description = "Auto-generated storyboard draft from events YAML. Review and refine rules/actions."

        return StoryboardDocument(
            version: 1,
            build: nil,
            scenario: StoryboardDocument.ScenarioMeta(
                name: name,
                description: description,
                owner: nil,
                tags: Array(tags).sorted()
            ),
            severity: nil,
            signals: signals,
            rules: rules,
            actions: [triage] + actions,
            timeline: timeline,
            fixtures: fixturesWithExpected
        )
    }

    private static func headlineFor(event: YAMLValue) -> String? {
        guard case .object(let dict) = event else { return nil }
        let keys = ["headline", "message", "title", "eventName", "action", "summary"]
        for key in keys {
            if let value = dict[key], case .string(let s) = value, !s.isEmpty {
                return String(s.prefix(90))
            }
        }
        return nil
    }

    private static func detailFor(event: YAMLValue) -> String? {
        guard case .object(let dict) = event else { return nil }
        var parts: [String] = []
        if let src = dict["source"], case .string(let s) = src { parts.append("source=\(s)") }
        if let user = dict["user"] ?? dict["username"] ?? dict["account"] ?? dict["principal"] ?? dict["userIdentity"], case .string(let s) = user { parts.append("user=\(s)") }
        if let ip = dict["ip"] ?? dict["src_ip"] ?? dict["sourceIPAddress"], case .string(let s) = ip { parts.append("ip=\(s)") }
        if let host = dict["host"] ?? dict["hostname"] ?? dict["device"] ?? dict["computer"], case .string(let s) = host { parts.append("host=\(s)") }
        if let proc = dict["process"] ?? dict["image"] ?? dict["exe"] ?? dict["ParentImage"], case .string(let s) = proc { parts.append("proc=\(s)") }
        if let target = dict["dst"] ?? dict["resource"] ?? dict["url"] ?? dict["domain"], case .string(let s) = target { parts.append("target=\(s)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func timeFor(event: YAMLValue) -> String {
        guard case .object(let dict) = event else { return "—" }
        let keys = ["time", "timestamp", "ts", "datetime", "eventTime", "@timestamp"]
        for key in keys {
            if let value = dict[key] {
                if case .string(let s) = value {
                    if let hhmm = extractTime(from: s) { return hhmm }
                    return s
                }
                if case .int(let i) = value { return formatEpoch(TimeInterval(i)) }
                if case .double(let d) = value { return formatEpoch(TimeInterval(d)) }
            }
        }
        return "—"
    }

    private static func extractTime(from string: String) -> String? {
        let isoSeparators: [Character] = ["T", " "]
        for sep in isoSeparators {
            if let range = string.split(separator: sep).last {
                let timePart = range.split(separator: "+").first?.split(separator: "Z").first ?? range[...]
                let comps = timePart.split(separator: ":")
                if comps.count >= 2 {
                    return comps.prefix(3).joined(separator: ":")
                }
            }
        }
        return nil
    }

    private static func formatEpoch(_ value: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: value)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func severityFor(event: YAMLValue) -> StoryboardDocument.Severity {
        let text = stringify(event: event).lowercased()
        let headline = headlineFor(event: event)?.lowercased() ?? ""
        let combined = headline + " " + text
        if matches(combined, ["tcc", "privacy prompt", "launchagent", "launchd", "unsigned binary", "persistence"]) {
            return .high
        }
        if matches(combined, ["curl ", "wget ", "download", "network"]) {
            return .medium
        }
        return .low
    }

    private static func matches(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0.lowercased()) }
    }

    private static func stringify(event: YAMLValue) -> String {
        switch event {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .null: return ""
        case .array(let arr): return arr.map { stringify(event: $0) }.joined(separator: " ")
        case .object(let dict):
            return dict.keys.sorted().compactMap { key in
                if let v = dict[key] { return "\(key)=\(stringify(event: v))" }
                return nil
            }.joined(separator: " ")
        }
    }

    private static func detectTags(from events: [YAMLValue]) -> Set<String> {
        var tags: Set<String> = ["macos", "imported"]
        for event in events {
            guard case .object(let dict) = event else { continue }
            let keys = Set(dict.keys.map { $0.lowercased() })
            let values = dict.values.compactMap { v -> String? in
                if case .string(let s) = v { return s.lowercased() }
                return nil
            }

            if keys.contains(where: { ["tcc","com.apple.tcc"].contains($0) }) || values.contains(where: { $0.contains("tcc") }) {
                tags.insert("tcc")
                tags.insert("privacy")
            }
            if keys.contains(where: { ["launchd","launchagent","launchagents","launchdaemons","plist"].contains($0) }) ||
                values.contains(where: { $0.contains("launchagent") || $0.contains("launchd") || $0.contains("plist") }) {
                tags.insert("persistence")
            }
            if keys.contains(where: { ["process","path","senderimagepath"].contains($0) }) ||
                values.contains(where: { $0.contains("bash") || $0.contains("zsh") || $0.contains("osascript") || $0.contains("python") || $0.contains("swift") || $0.contains("curl") || $0.contains("wget") }) {
                tags.insert("execution")
            }
            if keys.contains(where: { ["ip","src_ip","dst_ip","url","domain"].contains($0) }) {
                tags.insert("network")
            }
        }
        return tags
    }

    private static func detectSignals(from events: [YAMLValue]) -> [StoryboardDocument.Signal] {
        var signals: [StoryboardDocument.Signal] = []

        func add(id: String, label: String) {
            if !signals.contains(where: { $0.id == id }) {
                signals.append(StoryboardDocument.Signal(id: id, label: label))
            }
        }

        for event in events {
            guard case .object(let dict) = event else { continue }
            let keys = Set(dict.keys.map { $0.lowercased() })
            if keys.contains(where: { ["unified_log","subsystem","category"].contains($0) }) {
                add(id: "unified_log", label: "macOS Unified Logs")
            }
            if keys.contains(where: { ["process","senderimagepath","path"].contains($0) }) {
                add(id: "process", label: "Endpoint Process Telemetry")
            }
            if keys.contains(where: { ["ip","src_ip","dst_ip","url","domain"].contains($0) }) {
                add(id: "network", label: "Network Telemetry")
            }
            if keys.contains(where: { ["tcc","com.apple.tcc"].contains($0) }) || dict.values.contains(where: { if case .string(let s) = $0 { return s.lowercased().contains("tcc") } else { return false } }) {
                add(id: "tcc", label: "TCC / Privacy Events")
            }
        }

        return signals.sorted { $0.label < $1.label }
    }

    private static func deriveName(tags: Set<String>) -> String {
        return "Imported macOS Events"
    }

    private static func generateRules(from events: [YAMLValue], tags: Set<String>) -> [StoryboardDocument.Rule] {
        var findings: [(title: String, severity: StoryboardDocument.Severity, explanation: String, techniques: [String], match: [StoryboardDocument.RuleMatch])] = []

        let textBlob = events.map { stringify(event: $0).lowercased() }

        if textBlob.contains(where: { $0.contains("tcc") }) {
            findings.append((
                title: "Draft: TCC privacy prompt observed",
                severity: .high,
                explanation: "Draft detection: TCC/privacy prompts seen. Confirm app intent and user approval.",
                techniques: [],
                match: [StoryboardDocument.RuleMatch(ok: true, text: "event contains TCC/privacy prompt strings")]
            ))
        }

        if textBlob.contains(where: { $0.contains("launchagent") || $0.contains("launchd") || $0.contains("plist") }) {
            findings.append((
                title: "Draft: Potential persistence via LaunchAgents/Daemons",
                severity: .high,
                explanation: "Draft detection: LaunchAgent/Daemon patterns detected. Review persistence locations.",
                techniques: [],
                match: [StoryboardDocument.RuleMatch(ok: true, text: "event contains LaunchAgent/Daemon or plist writes")]
            ))
        }

        if textBlob.contains(where: { $0.contains("curl") || $0.contains("wget") || $0.contains("download") }) {
            findings.append((
                title: "Draft: Suspicious download/execution pattern",
                severity: .medium,
                explanation: "Draft detection: command-line download observed. Verify source, signature, and purpose.",
                techniques: [],
                match: [StoryboardDocument.RuleMatch(ok: true, text: "event contains curl/wget download or HTTP fetch")]
            ))
        }

        if textBlob.contains(where: { $0.contains("network") || $0.contains("ip=") || $0.contains("url=") || $0.contains("domain") }) {
            findings.append((
                title: "Draft: Outbound network indicator observed",
                severity: .medium,
                explanation: "Draft detection: network indicators present. Review destinations and frequency.",
                techniques: [],
                match: [StoryboardDocument.RuleMatch(ok: true, text: "event includes IP/URL/domain indicators")]
            ))
        }

        let deduped = findings
            .sorted { lhs, rhs in
                if lhs.severity == rhs.severity { return lhs.title < rhs.title }
                return severityRank(lhs.severity) > severityRank(rhs.severity)
            }
            .prefix(7)

        return deduped.enumerated().map { idx, item in
            StoryboardDocument.Rule(
                id: String(format: "RULE-IMPORTED-%03d", idx + 1),
                title: item.title,
                severity: item.severity,
                techniques: item.techniques,
                explanation: item.explanation,
                match: item.match
            )
        }
    }

    private static func severityRank(_ s: StoryboardDocument.Severity) -> Int {
        switch s {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .critical: return 4
        }
    }

    private static func buildActions(tags: Set<String>, hasHigh: Bool) -> [StoryboardDocument.Action] {
        var actions: [StoryboardDocument.Action] = []

        let macSteps = [
            "Inspect ~/Library/LaunchAgents and LaunchDaemons",
            "Review TCC prompts and recent approvals",
            "Check recent process trees and binaries for signing/notarization",
            "Review recent network connections and destinations",
            "Preserve plist paths, hashes, and relevant logs"
        ]
        let linuxSteps = [
            "Review auth.log/journalctl for repeated failures",
            "Inspect sshd configuration and recent users",
            "Check cron/systemd units for persistence"
        ]
        let cloudSteps = [
            "Search CloudTrail for recent role sessions",
            "Validate IAM key usage and rotate if suspicious",
            "Check unusual source IPs or regions"
        ]
        let windowsSteps = [
            "Review Event Logs for process creation and script blocks",
            "Inspect scheduled tasks and autoruns",
            "Check network connections and parent processes"
        ]

        let scoping = StoryboardDocument.Action(
            id: "ACT-SCOPING",
            title: "Scope & correlate (macOS)",
            steps: [
                "Group events by user/host/IP to find clusters",
                "Identify first/last seen times and sequences",
                "Pivot on shared indicators (hashes, domains, roles)"
            ],
            notes: "Capture for report: timestamps, user/host pairs, indicator list."
        )

        let contain = StoryboardDocument.Action(
            id: "ACT-CONTAIN",
            title: "Containment (macOS)",
            steps: [
                "Isolate affected hosts or user accounts",
                "Block known malicious destinations",
                "Preserve volatile data before cleanup"
            ],
            notes: nil
        )

        if tags.contains("macOS") {
            actions.append(StoryboardDocument.Action(id: "ACT-MAC", title: "macOS review", steps: macSteps, notes: nil))
        }
        if tags.contains("linux") {
            actions.append(StoryboardDocument.Action(id: "ACT-LINUX", title: "Linux review", steps: linuxSteps, notes: nil))
        }
        if tags.contains("cloud") {
            actions.append(StoryboardDocument.Action(id: "ACT-CLOUD", title: "Cloud review", steps: cloudSteps, notes: nil))
        }
        if tags.contains("windows") {
            actions.append(StoryboardDocument.Action(id: "ACT-WIN", title: "Windows review", steps: windowsSteps, notes: nil))
        }

        actions.insert(scoping, at: 0)
        if hasHigh { actions.append(contain) }
        return actions
    }

    private static func matchRules(for event: YAMLValue?, ruleIDs: [String]) -> [String] {
        guard let event, case .object(let dict) = event else { return [] }
        let text = stringify(event: .object(dict)).lowercased()
        var matched: [String] = []
        for id in ruleIDs {
            if id.contains("IMPORTED-") {
                if id.contains("LAUNCH") && text.contains("launch") { matched.append(id) }
                else if id.contains("TCC") && text.contains("tcc") { matched.append(id) }
                else if id.contains("AUTH") && text.contains("ssh") { matched.append(id) }
                else if id.contains("DOWNLOAD") && (text.contains("curl") || text.contains("wget")) { matched.append(id) }
                else if id.contains("ASSUME") && text.contains("assume") { matched.append(id) }
            }
        }
        return matched
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
