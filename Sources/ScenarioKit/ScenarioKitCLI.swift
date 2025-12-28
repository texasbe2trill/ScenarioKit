import ArgumentParser
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

    @Argument(help: "Path to a scenario YAML file.")
    var path: String

    func run() throws {
        print("analyze: \(path)")
        // Todo: load + parse + compute
    }
}
