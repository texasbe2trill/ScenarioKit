import ArgumentParser
import Foundation

@main
struct ScenarioKitCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scenariokit",
        abstract: "ScenarioKit — macOS security storyboards.",
        version: "1.0.0",
        subcommands: [StoryboardGroup.self, ValidateGroup.self, SysdiagnoseDump.self]
    )
}

struct StoryboardGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "storyboard",
        abstract: "Storyboard rendering tools.",
        subcommands: [StoryboardRender.self, StoryboardImportEvents.self]
    )
}

struct StoryboardRender: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render a storyboard HTML from a storyboard YAML/JSON."
    )

    enum StoryboardTheme: String, ExpressibleByArgument {
        case light
        case dark
    }

    @Argument(help: "Path to a storyboard file (yaml or json).")
    var path: String

    @Option(name: [.short, .long], help: "Output file path.")
    var out: String = "storyboard.html"

    @Option(name: .long, help: "Theme: light or dark.")
    var theme: StoryboardTheme = .dark

    @Option(name: .long, help: "Max fixtures to embed.")
    var maxEvents: Int = 200

    @Flag(name: .long, help: "Open the generated storyboard (macOS).")
    var open: Bool = false

    func run() throws {
        print("▸ Loading storyboard file...")
        let storyboard = try DocumentLoader.decodeStoryboard(atPath: path)
        if storyboard.fixtures.isEmpty {
            fputs("⚠️  storyboard render: parsed storyboard has zero fixtures; page may look sparse.\n", stderr)
        }
        print("▸ Rendering HTML...")
        let html = try StoryboardHTMLRenderer.render(
            storyboard: storyboard,
            theme: theme == .light ? .light : .dark,
            kind: .native,
            maxFixtures: maxEvents
        )
        print("▸ Writing output...")
        try OutputWriter.write(html, toPath: out)
        print("✔ Wrote storyboard to \(out)")
        if open {
            try openFile(at: out)
        }
    }
}

struct StoryboardImportEvents: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import-events",
        abstract: "Import macOS events and render a storyboard draft."
    )

    enum StoryboardTheme: String, ExpressibleByArgument {
        case light
        case dark
    }

    @Argument(help: "Path to an events file (json or yaml).")
    var path: String

    @Option(name: [.short, .long], help: "Output file path.")
    var out: String = "storyboard.html"

    @Option(name: .long, help: "Scenario name override.")
    var name: String?

    @Option(name: .long, help: "Theme: light or dark.")
    var theme: StoryboardTheme = .dark

    @Option(name: .long, help: "Max fixtures to embed.")
    var maxEvents: Int = 200

    @Flag(name: .long, help: "Open the generated storyboard (macOS).")
    var open: Bool = false

    func run() throws {
        print("▸ Loading events...")
        let anyValue = try DocumentLoader.decodeAnyValue(atPath: path)
        print("▸ Building storyboard draft...")
        let storyboard = try EventImport.importEvents(from: anyValue, sourceName: name)
        if storyboard.fixtures.isEmpty {
            fputs("⚠️  storyboard import: parsed events but built zero fixtures; check input file.\n", stderr)
        }
        print("▸ Rendering HTML...")
        let html = try StoryboardHTMLRenderer.render(
            storyboard: storyboard,
            theme: theme == .light ? .light : .dark,
            kind: .draft("Sigma matches"),
            maxFixtures: maxEvents
        )
        print("▸ Writing output...")
        try OutputWriter.write(html, toPath: out)
        print("✔ Wrote storyboard to \(out)")
        if open {
            try openFile(at: out)
        }
    }
}

// MARK: - Validation commands

struct ValidateGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate ScenarioKit inputs without rendering.",
        subcommands: [ValidateStoryboard.self, ValidateEvents.self]
    )
}

struct ValidateStoryboard: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "storyboard",
        abstract: "Validate a storyboard YAML/JSON file."
    )

    @Argument(help: "Path to a storyboard file (yaml or json).")
    var path: String

    func run() throws {
        print("▸ Validating storyboard...")
        _ = try DocumentLoader.decodeStoryboard(atPath: path)
        print("✔ Storyboard is valid")
    }
}

struct ValidateEvents: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "Validate an events JSON/YAML file (macOS logs)."
    )

    @Argument(help: "Path to an events file (json or yaml).")
    var path: String

    func run() throws {
        print("▸ Validating events...")
        let anyValue = try DocumentLoader.decodeAnyValue(atPath: path)
        _ = try EventImport.importEvents(from: anyValue, sourceName: nil)
        print("✔ Events file parsed and importable")
    }
}

// MARK: - Sysdiagnose helper

struct SysdiagnoseDump: ParsableCommand {
        static let configuration = CommandConfiguration(
                commandName: "sysdiagnose-dump",
                abstract: "Extract high-signal macOS security events from a sysdiagnose logarchive into JSON."
        )

        @Argument(help: "Path to the sysdiagnose system_logs.logarchive or parent sysdiagnose directory.")
        var path: String

        @Option(name: [.short, .long], help: "Output JSON file path.")
        var out: String = "macos_sysdiag_events.json"

        @Option(name: .long, help: "Lookback window, in minutes (passed to log show --last).")
        var minutes: Int = 120

        @Option(name: .long, help: "Override the default security-focused predicate for log show.")
        var predicate: String?

        @Flag(name: .long, help: "Write raw log show output (NDJSON). Default wraps output into a JSON array for import-events.")
        var raw: Bool = false

        @Flag(name: .long, help: "Include info/debug messages (slower and larger output).")
        var includeDebug: Bool = false

        func run() throws {
                let archivePath: String
                let fm = FileManager.default
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                        // If a directory, try to find system_logs.logarchive under it
                        let candidate = (path as NSString).appendingPathComponent("system_logs.logarchive")
                        archivePath = fm.fileExists(atPath: candidate) ? candidate : path
                } else {
                        archivePath = path
                }

                let predicate = predicate ?? Self.defaultPredicate
                let lastArg = "\(minutes)m"

                if !fm.fileExists(atPath: out) {
                    fm.createFile(atPath: out, contents: nil, attributes: nil)
                }

                print("▸ Running log show against \(archivePath) ...")
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/log")
                var args: [String] = ["show", "--style", "ndjson"]
                if includeDebug {
                    args += ["--info", "--debug"]
                }
                args += [
                    "--source",
                    "--archive", archivePath,
                    "--predicate", predicate,
                    "--last", lastArg
                ]
                proc.arguments = args
                proc.qualityOfService = .userInitiated

                let errPipe = Pipe()
                proc.standardError = errPipe

                var tempOutURL: URL?
                if raw {
                    let outURL = URL(fileURLWithPath: out)
                    let fh = try FileHandle(forWritingTo: outURL)
                    try fh.truncate(atOffset: 0)
                    proc.standardOutput = fh
                } else {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ndjson")
                    FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
                    let tempHandle = try FileHandle(forWritingTo: tempURL)
                    try tempHandle.truncate(atOffset: 0)
                    proc.standardOutput = tempHandle
                    tempOutURL = tempURL
                }

                do {
                    try proc.run()
                    proc.waitUntilExit()
                } catch {
                    throw ScenarioKitError.unableToOpenFile(archivePath, underlying: error)
                }

                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                if !errData.isEmpty, let errStr = String(data: errData, encoding: .utf8), !errStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fputs(errStr, stderr)
                }

                guard proc.terminationStatus == 0 else {
                    throw ScenarioKitError.unableToOpenFile(out, underlying: NSError(domain: "ScenarioKit", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "log show exited with code \(proc.terminationStatus)"]))
                }

                if raw {
                    print("✔ Wrote filtered events (raw NDJSON) to \(out)")
                } else if let tempURL = tempOutURL {
                    let data = try Data(contentsOf: tempURL)
                    let content = String(data: data, encoding: .utf8) ?? ""
                    let lines = content.split(whereSeparator: { $0.isNewline }).map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    let array = "[\n" + lines.joined(separator: ",\n") + "\n]"
                    try array.write(to: URL(fileURLWithPath: out), atomically: true, encoding: .utf8)
                    print("✔ Wrote filtered events (JSON array) to \(out)")
                }
        }

        private static let defaultPredicate = """
        (
            process CONTAINS[c] "curl" OR senderImagePath CONTAINS[c] "curl" OR eventMessage CONTAINS[c] "curl" OR eventMessage CONTAINS[c] "http"
        ) OR (
            subsystem CONTAINS[c] "tcc" OR eventMessage CONTAINS[c] "tcc" OR eventMessage CONTAINS[c] "privacy prompt" OR eventMessage CONTAINS[c] "access was denied"
        ) OR (
            eventMessage CONTAINS[c] "launchagent" OR eventMessage CONTAINS[c] "launchdaemon" OR eventMessage CONTAINS[c] ".plist"
        ) OR (
            subsystem CONTAINS[c] "dns" OR category CONTAINS[c] "dns" OR eventMessage CONTAINS[c] "resolver" OR eventMessage CONTAINS[c] "query"
        ) OR (
            eventMessage CONTAINS[c] "syspolicyd" OR eventMessage CONTAINS[c] "gatekeeper" OR eventMessage CONTAINS[c] "quarantine" OR eventMessage CONTAINS[c] "xprotect" OR eventMessage CONTAINS[c] "malware"
        )
        AND NOT (
            subsystem CONTAINS[c] "com.apple.windowserver" OR subsystem CONTAINS[c] "com.apple.metadata" OR subsystem CONTAINS[c] "com.apple.spotlight" OR subsystem CONTAINS[c] "com.apple.runningboard" OR subsystem CONTAINS[c] "com.apple.locationd" OR subsystem CONTAINS[c] "com.apple.defaults" OR category CONTAINS[c] "cfprefsd" OR process CONTAINS[c] "mds" OR process CONTAINS[c] "mdworker" OR process CONTAINS[c] "windowserver" OR process CONTAINS[c] "rapportd" OR process CONTAINS[c] "sharingd" OR process CONTAINS[c] "trustd" OR process CONTAINS[c] "cloudd" OR process CONTAINS[c] "backgroundshortcutrunner" OR process CONTAINS[c] "logd" OR process CONTAINS[c] "syslogd" OR process CONTAINS[c] "cfprefsd"
        )
        """
}

private func openFile(at path: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [path]
    do {
        try process.run()
    } catch {
        throw ScenarioKitError.unableToOpenFile(path, underlying: error)
    }
}
