import Foundation
import Yams

enum DocumentLoader {
    static func loadData(atPath path: String) throws -> Data {
        let url = URL(fileURLWithPath: path)
        return try Data(contentsOf: url)
    }

    static func decodeStoryboard(atPath path: String) throws -> StoryboardDocument {
        let data = try loadData(atPath: path)
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        var errors: [Error] = []

        if let doc: StoryboardDocument = try decode(StoryboardDocument.self, ext: ext, data: data, errors: &errors) {
            return doc
        }

        if let wrapped: ScenarioWrapper = try decode(ScenarioWrapper.self, ext: ext, data: data, errors: &errors) {
            return StoryboardDocument(
                version: 1,
                build: nil,
                scenario: wrapped.scenario,
                severity: nil,
                signals: [],
                rules: [],
                actions: [],
                timeline: [],
                fixtures: []
            )
        }

        if let scenario = try? decodeScenarioOnly(atPath: path, ext: ext, data: data) {
            return StoryboardDocument(
                version: 1,
                build: nil,
                scenario: scenario,
                severity: nil,
                signals: [],
                rules: [],
                actions: [],
                timeline: [],
                fixtures: []
            )
        }

        let readable = errors.compactMap { decodingSummary(for: $0) }.joined(separator: "; ")
        let message = readable.isEmpty ? "expected root key 'scenario' or a storyboard document" : readable
        let err = NSError(domain: "ScenarioKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid storyboard YAML: \(message)"])
        throw ScenarioKitError.invalidStoryboardYAML(underlying: err)
    }

    static func decodeAnyValue(atPath path: String) throws -> YAMLValue {
        let data = try loadData(atPath: path)
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "json":
            return try JSONDecoder().decode(YAMLValue.self, from: data)
        case "yaml", "yml":
            return try YAMLDecoder().decode(YAMLValue.self, from: data)
        default:
            if let val = try? JSONDecoder().decode(YAMLValue.self, from: data) {
                return val
            }
            do {
                return try YAMLDecoder().decode(YAMLValue.self, from: data)
            } catch {
                throw ScenarioKitError.invalidStoryboardYAML(underlying: error)
            }
        }
    }

    private static func decodeScenarioOnly(atPath path: String, ext: String, data: Data) throws -> StoryboardDocument.ScenarioMeta {
        switch ext {
        case "json":
            return try JSONDecoder().decode(StoryboardDocument.ScenarioMeta.self, from: data)
        case "yaml", "yml":
            return try YAMLDecoder().decode(StoryboardDocument.ScenarioMeta.self, from: data)
        default:
            if let scenario = try? JSONDecoder().decode(StoryboardDocument.ScenarioMeta.self, from: data) {
                return scenario
            }
            return try YAMLDecoder().decode(StoryboardDocument.ScenarioMeta.self, from: data)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, ext: String, data: Data, errors: inout [Error]) throws -> T? {
        switch ext {
        case "json":
            do { return try JSONDecoder().decode(T.self, from: data) } catch { errors.append(error); return nil }
        case "yaml", "yml":
            do { return try YAMLDecoder().decode(T.self, from: data) } catch { errors.append(error); return nil }
        default:
            do { return try JSONDecoder().decode(T.self, from: data) } catch { errors.append(error) }
            do { return try YAMLDecoder().decode(T.self, from: data) } catch { errors.append(error); return nil }
        }
    }

    private static func decodingSummary(for error: Error) -> String? {
        guard let decodingError = error as? DecodingError else { return error.localizedDescription }
        switch decodingError {
        case .keyNotFound(let key, let context):
            let path = (context.codingPath.map { $0.stringValue }.joined(separator: "."))
            return "missing key '\(key.stringValue)' at \(path)"
        case .valueNotFound(let type, let context):
            let path = (context.codingPath.map { $0.stringValue }.joined(separator: "."))
            return "missing value for \(type) at \(path)"
        case .typeMismatch(let type, let context):
            let path = (context.codingPath.map { $0.stringValue }.joined(separator: "."))
            return "type mismatch for \(type) at \(path)"
        case .dataCorrupted(let context):
            return "data corrupted: \(context.debugDescription)"
        @unknown default:
            return decodingError.localizedDescription
        }
    }
}

private struct ScenarioWrapper: Decodable {
    let scenario: StoryboardDocument.ScenarioMeta
}
