import ArgumentParser

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

    func run() throws {
        print("validate: \(path)")
        // Todo: load + parse + validate
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