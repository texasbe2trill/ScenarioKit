import ArgumentParser
import Foundation

@main
struct ScenarioKitCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scenariokit",
        abstract: "ScenarioKit — macOS security storyboards.",
        subcommands: [StoryboardGroup.self]
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
            kind: .draft("Imported macOS Events"),
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
