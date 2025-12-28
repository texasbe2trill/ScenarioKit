import ArgumentParser
import Foundation
import Yams

@main
struct ScenarioKitCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scenariokit",
        abstract: "ScenarioKit — security scenario modeling from YAML.",
        subcommands: [Validate.self, Analyze.self]
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

        switch format {
        case .text:
            print("✔ Services: \(report.serviceCount)")
            report.services.forEach { node in
                let dependsOn = node.dependsOn.isEmpty ? "(none)" : node.dependsOn.joined(separator: ", ")
                let dependents = node.dependents.isEmpty ? "(none)" : node.dependents.joined(separator: ", ")
                print("- \(node.name)")
                print("  depends_on: \(dependsOn)")
                print("  dependents: \(dependents)")
            }
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                let data = try encoder.encode(report)
                if let output = String(data: data, encoding: .utf8) {
                    print(output)
                }
            } catch {
                throw ScenarioKitError.jsonEncodingFailed(underlying: error)
            }
        }
    }
}
