import ArgumentParser
import Foundation
import Yams

@main
struct ScenarioKitCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scenariokit",
        abstract: "ScenarioKit — security scenario modeling from YAML.",
        subcommands: [Validate.self, Analyze.self, Report.self, StoryboardGroup.self]
    )
}

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Validate a scenario manifest."
    )

    @Argument(help: "Path to a scenario YAML file.")
    var path: String

    @Flag(name: .shortAndLong, help: "Treat warnings as errors.")
    var strict: Bool = false

    func run() throws {
        let text = try FileLoader.loadText(atPath: path)
        print("✔ Loaded \(path) (\(text.utf8.count) bytes)")

        let scenario: Scenario
        do {
            scenario = try YAMLDecoder().decode(Scenario.self, from: text)
        } catch {
            throw ScenarioKitError.invalidYAML(path, underlying: error)
        }

        let parsedName = scenario.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "<unknown>" : scenario.name
        print("✔ Parsed scenario: \(parsedName)")

        let issues = ScenarioValidator.validate(scenario)
        let errors = issues.filter { $0.severity == .error }
        let warnings = issues.filter { $0.severity == .warning }

        if issues.isEmpty {
            print("✔ No validation issues")
            return
        }

        errors.forEach { print("✖ error: \($0.message)") }
        warnings.forEach { print("⚠︎ warning: \($0.message)") }

        if !errors.isEmpty {
            throw ScenarioKitError.validationFailed("\(errors.count) error(s) found")
        }

        if strict && !warnings.isEmpty {
            throw ScenarioKitError.validationFailed("warnings treated as errors (\(warnings.count))")
        }
    }
}

struct Analyze: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Analyze a scenario manifest (blast radius, criticality, etc.)."
    )

    enum OutputFormat: String, ExpressibleByArgument {
        case text
        case json
    }

    @Argument(help: "Path to a scenario YAML file.")
    var path: String

    @Option(name: .shortAndLong, help: "Output format: text or json.")
    var format: OutputFormat = .text

    @Option(name: [.short, .long], help: "Write output to a file instead of stdout.")
    var output: String?

    func run() throws {
        let text = try FileLoader.loadText(atPath: path)
        print("✔ Loaded \(path) (\(text.utf8.count) bytes)")

        let scenario: Scenario
        do {
            scenario = try YAMLDecoder().decode(Scenario.self, from: text)
        } catch {
            throw ScenarioKitError.invalidYAML(path, underlying: error)
        }

        let parsedName = scenario.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "<unknown>" : scenario.name
        print("✔ Parsed scenario: \(parsedName)")

        let issues = ScenarioValidator.validate(scenario)
        let errors = issues.filter { $0.severity == .error }
        let warnings = issues.filter { $0.severity == .warning }

        if issues.isEmpty {
            print("✔ No validation issues")
        } else {
            errors.forEach { print("✖ error: \($0.message)") }
            warnings.forEach { print("⚠︎ warning: \($0.message)") }

            if !errors.isEmpty {
                throw ScenarioKitError.validationFailed("\(errors.count) error(s) found")
            }
        }

        let report = ScenarioAnalyzer.analyze(scenario)

        let renderedOutput: String
        switch format {
        case .text:
            renderedOutput = renderText(report: report)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                let data = try encoder.encode(report)
                guard let output = String(data: data, encoding: .utf8) else {
                    throw ScenarioKitError.jsonEncodingFailed(underlying: CocoaError(.coderInvalidValue))
                }
                renderedOutput = output
            } catch {
                throw ScenarioKitError.jsonEncodingFailed(underlying: error)
            }
        }

        if let outputPath = output {
            try OutputWriter.write(renderedOutput, toPath: outputPath)
            print("✔ Wrote output to \(outputPath)")
        } else {
            print(renderedOutput)
        }
    }

    private func renderText(report: AnalysisReport) -> String {
        var lines: [String] = []
        lines.append("✔ Services: \(report.serviceCount)")
        for node in report.services {
            let dependsOn = node.dependsOn.isEmpty ? "(none)" : node.dependsOn.joined(separator: ", ")
            let dependents = node.dependents.isEmpty ? "(none)" : node.dependents.joined(separator: ", ")
            lines.append("- \(node.name)")
            lines.append("  depends_on: \(dependsOn)")
            lines.append("  dependents: \(dependents)")
        }
        return lines.joined(separator: "\n")
    }
}

struct Report: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate an HTML or JSON report for a scenario."
    )

    enum ReportFormat: String, ExpressibleByArgument {
        case html
        case json
    }

    @Argument(help: "Path to a scenario YAML file.")
    var path: String

    @Option(name: [.short, .long], help: "Output file path.")
    var out: String = "report.html"

    @Option(name: .long, help: "Report format: html or json.")
    var format: ReportFormat = .html

    @Flag(name: .long, help: "Open the generated HTML report (macOS).")
    var open: Bool = false

    @Flag(name: .long, help: "Treat warnings as errors.")
    var strict: Bool = false

    func run() throws {
        let text = try FileLoader.loadText(atPath: path)

        let scenario: Scenario
        do {
            scenario = try YAMLDecoder().decode(Scenario.self, from: text)
        } catch {
            throw ScenarioKitError.invalidYAML(path, underlying: error)
        }

        let issues = ScenarioValidator.validate(scenario)
        let errors = issues.filter { $0.severity == .error }
        let warnings = issues.filter { $0.severity == .warning }

        if !errors.isEmpty {
            throw ScenarioKitError.validationFailed("\(errors.count) error(s) found")
        }

        if strict && !warnings.isEmpty {
            throw ScenarioKitError.validationFailed("warnings treated as errors (\(warnings.count))")
        }

        let analysis = ScenarioAnalyzer.analyze(scenario)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData: Data
        do {
            jsonData = try encoder.encode(analysis)
        } catch {
            throw ScenarioKitError.jsonEncodingFailed(underlying: error)
        }
        guard let reportJSON = String(data: jsonData, encoding: .utf8) else {
            throw ScenarioKitError.jsonEncodingFailed(underlying: CocoaError(.coderInvalidValue))
        }

        switch format {
        case .json:
            try OutputWriter.write(reportJSON, toPath: out)
            print("✔ Wrote report to \(out)")
        case .html:
            let mermaidGraph = ReportRenderer.mermaidGraph(for: analysis)
            let summary = ReportRenderer.summary(for: analysis)
            let mermaidScript = try loadMermaidScript()
            let title = scenario.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Scenario Report" : scenario.name
            let html = HTMLTemplate.render(
                title: title,
                mermaid: mermaidGraph,
                reportJSON: reportJSON,
                summary: summary,
                issues: issues,
                mermaidScript: mermaidScript
            )
            try OutputWriter.write(html, toPath: out)
            print("✔ Wrote report to \(out)")

            if open {
                try openFile(at: out)
            }
        }
    }

    private func loadMermaidScript() throws -> String {
        guard let url = Bundle.module.url(forResource: "mermaid", withExtension: "min.js") else {
            throw ScenarioKitError.mermaidResourceMissing
        }
        do {
            return try String(contentsOf: url)
        } catch {
            throw ScenarioKitError.mermaidResourceMissing
        }
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
        abstract: "Render a storyboard HTML from a storyboard YAML."
    )

    enum StoryboardTheme: String, ExpressibleByArgument {
        case light
        case dark
    }

    @Argument(help: "Path to a storyboard YAML file.")
    var path: String

    @Option(name: [.short, .long], help: "Output file path.")
    var out: String = "storyboard.html"

    @Option(name: .long, help: "Theme: light or dark.")
    var theme: StoryboardTheme = .dark

    @Flag(name: .long, help: "Open the generated storyboard (macOS).")
    var open: Bool = false

    func run() throws {
        let text = try FileLoader.loadText(atPath: path)
        let storyboard: StoryboardDocument
        do {
            storyboard = try YAMLDecoder().decode(StoryboardDocument.self, from: text)
        } catch {
            throw ScenarioKitError.invalidStoryboardYAML(underlying: error)
        }

        let issues = storyboardIssues(for: storyboard)
        if issues.contains(where: { $0.severity == .error }) {
            let count = issues.filter { $0.severity == .error }.count
            throw ScenarioKitError.validationFailed("\(count) error(s) found")
        }

        let html = try StoryboardHTMLRenderer.render(
            storyboard: storyboard,
            theme: theme == .light ? .light : .dark,
            kind: .native
        )
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
        abstract: "Import events YAML and render a storyboard HTML."
    )

    enum StoryboardTheme: String, ExpressibleByArgument {
        case light
        case dark
    }

    @Argument(help: "Path to an events YAML file.")
    var path: String

    @Option(name: [.short, .long], help: "Output file path.")
    var out: String = "storyboard.html"

    @Option(name: .long, help: "Scenario name override.")
    var name: String?

    @Option(name: .long, help: "Theme: light or dark.")
    var theme: StoryboardTheme = .dark

    @Flag(name: .long, help: "Open the generated storyboard (macOS).")
    var open: Bool = false

    func run() throws {
        let text = try FileLoader.loadText(atPath: path)
        let anyYAML = try EventImport.parseYAML(text)

        let storyboard = try EventImport.importEvents(from: anyYAML, sourceName: name)
        let html = try StoryboardHTMLRenderer.render(
            storyboard: storyboard,
            theme: theme == .light ? .light : .dark,
            kind: .draft("Imported macOS Events")
        )
        try OutputWriter.write(html, toPath: out)
        print("✔ Wrote storyboard to \(out)")

        if open {
            try openFile(at: out)
        }
    }
}

private func storyboardIssues(for storyboard: StoryboardDocument) -> [ScenarioIssue] {
    var issues: [ScenarioIssue] = []

    if storyboard.scenario.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.error("Scenario name is required."))
    }

    var seen: Set<String> = []
    for rule in storyboard.rules {
        if !seen.insert(rule.id).inserted {
            issues.append(.error("Duplicate rule id: \(rule.id)"))
        }
    }

    let ruleIDs = Set(storyboard.rules.map { $0.id })
    for fixture in storyboard.fixtures {
        for expected in fixture.expected ?? [] where !ruleIDs.contains(expected) {
            issues.append(.warning("Fixture \(fixture.id) expects missing rule id \(expected)"))
        }
    }

    return issues
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
