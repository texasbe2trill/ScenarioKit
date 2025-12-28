import XCTest
@testable import ScenarioKit

final class ScenarioKitTests: XCTestCase {
    func testTimelineBuildsFromEventContent() throws {
        let events: [YAMLValue] = [
            .object([
                "timestamp": .string("2024-05-01T10:11:12Z"),
                "eventMessage": .string("App crashed"),
                "subsystem": .string("com.apple.test"),
                "category": .string("Crash"),
                "process": .string("SampleApp")
            ]),
            .object([
                "timestamp": .string("2024-05-01T10:12:00Z"),
                "eventMessage": .string("Network connect"),
                "subsystem": .string("net"),
                "category": .string("Connection"),
                "process": .string("curl")
            ])
        ]

        let storyboard = try EventImport.importEvents(from: .array(events), sourceName: "Test Story")

        XCTAssertEqual(storyboard.timeline.count, 2)
        XCTAssertEqual(storyboard.timeline[0].time, "2024-05-01T10:11:12Z")
        XCTAssertEqual(storyboard.timeline[1].time, "2024-05-01T10:12:00Z")
        XCTAssertFalse(storyboard.timeline[0].headline.hasPrefix("Event "))
        XCTAssertFalse(storyboard.timeline[1].headline.hasPrefix("Event "))
        XCTAssertFalse(storyboard.timeline[0].detail?.isEmpty ?? true)
        XCTAssertFalse(storyboard.timeline[1].detail?.isEmpty ?? true)
    }

    func testScenarioOnlyFileWrapsAndRenders() throws {
        let scenarioOnlyJSON = """
        {
          "name": "Wrapped Scenario",
          "description": "Root is just scenario"
        }
        """.data(using: .utf8)!

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("scenario-only.json")
        try scenarioOnlyJSON.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let storyboard = try DocumentLoader.decodeStoryboard(atPath: tmp.path)
        XCTAssertEqual(storyboard.scenario.name, "Wrapped Scenario")
        XCTAssertTrue(storyboard.fixtures.isEmpty)
    }

    func testImportEventsProducesFixturesAndHTMLHasFixtureId() throws {
        let events: [YAMLValue] = [
            .object([
                "timestamp": .string("2024-05-02T10:11:12Z"),
                "eventMessage": .string("App crashed"),
                "subsystem": .string("com.apple.test")
            ])
        ]

        let storyboard = try EventImport.importEvents(from: .array(events), sourceName: "HTML Test")
        XCTAssertFalse(storyboard.fixtures.isEmpty)
        let html = try StoryboardHTMLRenderer.render(
            storyboard: storyboard,
            theme: .dark,
            kind: .draft("Test"),
            maxFixtures: 10
        )
        XCTAssertTrue(html.contains("EVT-001"), "HTML should include fixture IDs")
    }

    func testRenderedHTMLEmbedsTimelineMessages() throws {
        let events: [YAMLValue] = [
            .object([
                "timestamp": .string("2024-05-02T10:11:12Z"),
                "eventMessage": .string("App crashed"),
                "subsystem": .string("com.apple.test")
            ])
        ]

        let storyboard = try EventImport.importEvents(from: .array(events), sourceName: "HTML Test")
        let html = try StoryboardHTMLRenderer.render(
            storyboard: storyboard,
            theme: .dark,
            kind: .draft("Test"),
            maxFixtures: 10
        )

        XCTAssertTrue(html.contains("App crashed"), "HTML should embed event message in timeline JSON")
        XCTAssertFalse(html.contains("\"headline\" : \"Event 1\""), "HTML should not use placeholder Event labels")
    }

    func testNoiseFilteringKeepsInterestingEvents() throws {
        let events: [YAMLValue] = [
            .object([
                "timestamp": .string("2024-05-02T10:11:12Z"),
                "process": .string("rapportd"),
                "subsystem": .string("com.apple.runningboard"),
                "eventMessage": .string("")
            ]),
            .object([
                "timestamp": .string("2024-05-02T10:12:00Z"),
                "process": .string("curl"),
                "subsystem": .string("com.apple.network"),
                "eventMessage": .string("Outgoing HTTPS request")
            ])
        ]

        let storyboard = try EventImport.importEvents(from: .array(events), sourceName: "Noise Test")
        XCTAssertEqual(storyboard.fixtures.count, 1)
        XCTAssertEqual(storyboard.fixtures.first?.id, "EVT-001")
        XCTAssertTrue(storyboard.timeline.first?.headline.lowercased().contains("https") ?? false)
    }

    func testExampleStoryboardRendersAndInjectsData() throws {
        let path = fixturePath("examples/storyboard_macos_example.yaml")
        let storyboard = try DocumentLoader.decodeStoryboard(atPath: path)
        let html = try StoryboardHTMLRenderer.render(
            storyboard: storyboard,
            theme: .dark,
            kind: .native,
            maxFixtures: 10
        )

        guard let payload = extractDataBlock(from: html) else {
            return XCTFail("Expected SCENARIOKIT data markers to be present")
        }

        XCTAssertTrue(payload.contains("window.__SCENARIOKIT__ ="))
        XCTAssertTrue(payload.contains("Outbound HTTPS request to api.example.com:443"))
    }

    func testImportEventsInjectsFixturesIntoHTML() throws {
        let path = fixturePath("examples/macos_events_example.json")
        let anyValue = try DocumentLoader.decodeAnyValue(atPath: path)
        let storyboard = try EventImport.importEvents(from: anyValue, sourceName: "Example Events")
        let html = try StoryboardHTMLRenderer.render(
            storyboard: storyboard,
            theme: .dark,
            kind: .draft("Imported macOS Events"),
            maxFixtures: 10
        )

        guard let payload = extractDataBlock(from: html) else {
            return XCTFail("Expected SCENARIOKIT data markers to be present")
        }

        XCTAssertTrue(payload.contains("window.__SCENARIOKIT__ ="))
        XCTAssertTrue(payload.contains("EVT-001"))
    }

    private func extractDataBlock(from html: String) -> String? {
        guard let start = html.range(of: "/* SCENARIOKIT_DATA_START */"),
              let end = html.range(of: "/* SCENARIOKIT_DATA_END */", range: start.upperBound..<html.endIndex) else { return nil }
        return String(html[start.lowerBound..<end.upperBound])
    }

    private func fixturePath(_ relative: String) -> String {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = testsDir.deletingLastPathComponent().deletingLastPathComponent()
        return root.appendingPathComponent(relative).path
    }
}
