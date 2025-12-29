import Foundation
import Yams

enum EventImport {
    static func importEvents(from anyYAML: YAMLValue, sourceName: String?) throws -> StoryboardDocument {
        let rawEvents: [YAMLValue]
        switch anyYAML {
        case .array(let arr):
            rawEvents = arr
        case .object(let dict):
            if let ev = dict["events"], case .array(let arr) = ev {
                rawEvents = arr
            } else if let items = dict["items"], case .array(let arr) = items {
                rawEvents = arr
            } else {
                throw ScenarioKitError.unsupportedEventsImport
            }
        default:
            throw ScenarioKitError.unsupportedEventsImport
        }

        let noiseFiltered = filterNoise(from: rawEvents)

        if noiseFiltered.isEmpty {
            fputs("⚠️  storyboard import: all events filtered as noise; check input predicates or broaden filters.\n", stderr)
        } else if noiseFiltered.count < rawEvents.count {
            fputs("ℹ️  storyboard import: filtered \(rawEvents.count - noiseFiltered.count) noisy events (kept \(noiseFiltered.count) of \(rawEvents.count)).\n", stderr)
        }

        let sigmaEngine = SigmaMatcher.shared
        let matchedTuples: [(event: YAMLValue, matches: [String])]
        if let sigmaEngine {
            let results = sigmaEngine.match(events: noiseFiltered)
            if results.isEmpty {
                fputs("⚠️  sigma: no events matched bundled macOS Sigma rules; falling back to importer-selected events.\n", stderr)
                matchedTuples = noiseFiltered.map { ($0, []) }
            } else {
                matchedTuples = results
                if results.count < noiseFiltered.count {
                    fputs("ℹ️  sigma: kept \(results.count) of \(noiseFiltered.count) events that matched Sigma macOS rules.\n", stderr)
                }
            }
        } else {
            matchedTuples = noiseFiltered.map { ($0, []) }
        }

        let matchedEvents = matchedTuples.map { $0.event }
        let tags = detectTags(from: matchedEvents)
        let signals = detectSignals(from: matchedEvents)

        let maxTimelineItems = 100
        var timeline = matchedTuples.map { $0.event }
            .prefix(maxTimelineItems)
            .enumerated()
            .map { idx, val in timelineItem(for: val, index: idx) }

        if timeline.isEmpty {
            fputs("⚠️  storyboard import: no timeline items built from events; inserting placeholder.\\n", stderr)
            timeline = [
                StoryboardDocument.TimelineItem(
                    time: "—",
                    headline: "No events loaded",
                    detail: "Import produced no timeline entries",
                    severity: .low
                )
            ]
        }

        let fixtures: [StoryboardDocument.Fixture] = matchedTuples.enumerated().map { idx, tuple in
            StoryboardDocument.Fixture(
                id: String(format: "EVT-%03d", idx + 1),
                expected: tuple.matches.isEmpty ? [] : tuple.matches,
                result: tuple.matches.isEmpty ? "unknown" : "match",
                event: tuple.event,
                matchedRules: tuple.matches
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

        let matchedRuleIDs = Set(matchedTuples.flatMap { $0.matches })
        let rules: [StoryboardDocument.Rule]
        if let sigmaEngine {
            let sigmaRules = sigmaEngine.rules(for: matchedRuleIDs)
            rules = sigmaRules.map { r in
                StoryboardDocument.Rule(
                    id: r.id,
                    title: r.title,
                    severity: .medium,
                    techniques: [],
                    explanation: r.description,
                    match: [StoryboardDocument.RuleMatch(ok: true, text: r.condition)]
                )
            }
        } else {
            rules = generateRules(from: matchedEvents, tags: tags)
        }

        let ruleIDs = rules.map { $0.id }

        let fixturesWithExpected = fixtures.map { fixture -> StoryboardDocument.Fixture in
            let expected = matchRules(for: fixture.event, ruleIDs: ruleIDs)
            return StoryboardDocument.Fixture(
                id: fixture.id,
                expected: expected.isEmpty ? fixture.expected : expected,
                result: fixture.result,
                event: fixture.event,
                matchedRules: fixture.matchedRules
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

    private static func timelineItem(for event: YAMLValue, index: Int) -> StoryboardDocument.TimelineItem {
        let headline = headlineFor(event: event) ?? fallbackHeadline(for: event, index: index)
        let detail = detailFor(event: event) ?? fallbackDetail(for: event, headline: headline)
        let time = timeFor(event: event)
        let severity = severityFor(event: event)
        return StoryboardDocument.TimelineItem(
            time: time,
            headline: headline,
            detail: detail,
            severity: severity
        )
    }

    private static func fallbackHeadline(for event: YAMLValue, index: Int) -> String {
        if case .object(let dict) = event {
            let subsystem = string(for: ["subsystem"], in: dict)
            let category = string(for: ["category"], in: dict)
            let combined = [subsystem, category].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !combined.isEmpty {
                return combined.joined(separator: " / ")
            }
        }
        return "Event \(index + 1)"
    }

    private static func fallbackDetail(for event: YAMLValue, headline: String) -> String? {
        guard case .object(let dict) = event else { return headline.isEmpty ? nil : headline }
        var parts: [String] = []
        if let subsystem = string(for: ["subsystem"], in: dict) { parts.append("subsystem=\(subsystem)") }
        if let category = string(for: ["category"], in: dict) { parts.append("category=\(category)") }
        if let process = string(for: ["process", "image", "exe", "ParentImage", "processName"], in: dict) { parts.append("process=\(process)") }
        if let user = string(for: ["user", "username", "account", "principal", "userIdentity"], in: dict) { parts.append("user=\(user)") }
        if let host = string(for: ["host", "hostname", "device", "computer"], in: dict) { parts.append("host=\(host)") }
        if let ip = string(for: ["ip", "src_ip", "sourceIPAddress"], in: dict) { parts.append("ip=\(ip)") }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return headline.isEmpty ? nil : headline
    }

    private static func string(for keys: [String], in dict: [String: YAMLValue]) -> String? {
        for key in keys {
            if let value = dict[key], case .string(let s) = value {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func headlineFor(event: YAMLValue) -> String? {
        guard case .object(let dict) = event else { return nil }
        let keys = ["headline", "eventMessage", "message", "title", "eventName", "action", "summary"]
        for key in keys {
            if let value = dict[key], case .string(let s) = value, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return String(s.prefix(140))
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
        if let subsystem = dict["subsystem"], case .string(let s) = subsystem, !s.isEmpty { parts.append("subsystem=\(s)") }
        if let category = dict["category"], case .string(let s) = category, !s.isEmpty { parts.append("category=\(s)") }
        if let msg = dict["eventMessage"], case .string(let s) = msg, parts.isEmpty {
            return String(s.prefix(160))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func timeFor(event: YAMLValue) -> String {
        guard case .object(let dict) = event else { return "—" }
        let keys = ["timestamp", "time", "ts", "datetime", "eventTime", "@timestamp"]
        for key in keys {
            if let value = dict[key] {
                if case .string(let s) = value {
                    return s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if case .int(let i) = value { return formatEpoch(TimeInterval(i)) }
                if case .double(let d) = value { return formatEpoch(TimeInterval(d)) }
            }
        }
        return "—"
    }

    private static func formatEpoch(_ value: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: value)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
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

    private static func filterNoise(from events: [YAMLValue]) -> [YAMLValue] {
        var dedupe: [String: Int] = [:]
        var timeDedupe: [String: Date] = [:]
        var kept: [YAMLValue] = []

        for event in events {
            guard case .object(let dict) = event else {
                kept.append(event); continue
            }

            let message = string(for: ["eventMessage", "message", "summary", "title", "composedMessage"], in: dict)?.lowercased() ?? ""
            let process = string(for: ["process", "image", "exe", "ParentImage", "processName"], in: dict)?.lowercased() ?? ""
            let subsystem = string(for: ["subsystem", "system"], in: dict)?.lowercased() ?? ""
            let category = string(for: ["category"], in: dict)?.lowercased() ?? ""
            let messageType = string(for: ["messageType"], in: dict)?.lowercased() ?? ""
            let timestamp = eventTimestamp(in: dict)

            let text = (message + " " + process + " " + subsystem + " " + category)
            let hasKeyword = interestingKeywords.contains { text.contains($0) }
            let noisySubsystem = noiseSubsystems.contains(subsystem)
            let noisyProcess = noiseProcesses.contains(process)
            let spotlightNoise = process.hasPrefix("mds") || process.hasPrefix("mdworker") || subsystem.contains("metadata") || subsystem.contains("spotlight")
            let windowServerNoise = process.contains("windowserver") || subsystem.contains("windowserver")

            // Always keep curl/network-ish even if subsystem absent
            let isCurlish = process.contains("curl") || process.contains("wget") || message.contains("http") || message.contains("https")

            let matchesNoisePattern = noiseMessagePatterns.contains(where: { pattern in message.contains(pattern) })

            // EDR-like stance: if nothing interesting and not curlish, drop early
            if !hasKeyword && !isCurlish { continue }
            // Drop low-value Default chatter unless curlish
            if !isCurlish && messageType == "default" && !hasKeyword { continue }
            // Drop known sandbox/XPC churn
            if !hasKeyword && !isCurlish && matchesNoisePattern { continue }

            let sandboxDefaultsNoise = (subsystem.contains("com.apple.defaults") || category.contains("cfprefsd")) && (message.contains("rejecting read") || message.contains("kcfpreferencesanyhost"))
            if !hasKeyword && !isCurlish && sandboxDefaultsNoise { continue }

            if !hasKeyword && !isCurlish && message.isEmpty && noisySubsystem { continue }
            if !hasKeyword && !isCurlish && noisyProcess && message.count < 6 { continue }
            if !hasKeyword && !isCurlish && windowServerNoise { continue }
            if !hasKeyword && !isCurlish && spotlightNoise && message.count < 80 { continue }

            let dedupeKey = "\(process)|\(subsystem)|\(message)"
            if let ts = timestamp {
                if let last = timeDedupe[dedupeKey], ts.timeIntervalSince(last) < 30, !hasKeyword && !isCurlish { continue }
                timeDedupe[dedupeKey] = ts
            } else {
                let seen = dedupe[dedupeKey, default: 0]
                if seen >= 1 && !hasKeyword && !isCurlish { continue }
                dedupe[dedupeKey] = seen + 1
            }

            kept.append(event)
        }

        return kept
    }

    private static func eventTimestamp(in dict: [String: YAMLValue]) -> Date? {
        let keys = ["timestamp", "time", "ts", "datetime", "eventTime", "@timestamp"]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for key in keys {
            if let value = dict[key] {
                switch value {
                case .string(let s):
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let date = formatter.date(from: trimmed) { return date }
                case .int(let i):
                    return Date(timeIntervalSince1970: TimeInterval(i))
                case .double(let d):
                    return Date(timeIntervalSince1970: TimeInterval(d))
                default:
                    continue
                }
            }
        }
        return nil
    }

    private static let interestingKeywords: [String] = [
        "curl", "wget", "http", "https", "download", "egress", "network", "dns", "connection", "connect",
        "tcc", "privacy", "prompt", "denied", "allow", "keychain", "credential", "auth", "authentication",
        "launchagent", "launchdaemon", "plist", "persistence", "loginitem", "launchd",
        "sudo", "root", "elevated", "malware", "xprotect", "quarantine", "notarized", "unsigned",
        "bash", "zsh", "sh -c", "osascript", "python", "command line"
    ]

    private static let noiseSubsystems: Set<String> = [
        "com.apple.runningboard", "com.apple.locationd", "com.apple.audio", "com.apple.imfoundation", "com.apple.wifi",
        "com.apple.coremedia", "com.apple.coretelephony", "com.apple.multipeerconnectivity", "com.apple.backboardd",
        "com.apple.metadata.mds", "com.apple.metadata", "com.apple.spotlight", "com.apple.windowserver", "com.apple.defaults"
    ]

    private static let noiseProcesses: Set<String> = [
        "rapportd", "sharingd", "bird", "cloudd", "trustd", "mds", "mdworker", "mds_stores", "windowserver",
        "logd", "syslogd", "cfprefsd", "distnoted", "usereventagent", "backgroundshortcutrunner"
    ]

    private static let noiseMessagePatterns: [String] = [
        "xpc_error_connection_invalid",
        "sandbox is preventing this process",
        "job not found, returning enoservice",
        "rejecting write of key(s)",
        "rejecting read of",
        "requires user-preference-read",
        "kcfpreferencesanyhost"
    ]

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
