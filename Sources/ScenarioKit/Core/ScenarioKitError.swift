import Foundation

enum ScenarioKitError: LocalizedError {
    case fileNotFound(String)
    case unreadableFile(String, underlying: Error)
    case invalidYAML(String, underlying: Error)
    case validationFailed(String)
    case jsonEncodingFailed(underlying: Error)
    case unableToWriteFile(String, underlying: Error)
    case unableToOpenFile(String, underlying: Error)
    case mermaidResourceMissing
    case invalidStoryboardYAML(underlying: Error)
    case unsupportedEventsImport

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .unreadableFile(let path, let underlying):
            return "Could not read \(path): \(underlying.localizedDescription)"
        case .invalidYAML(let path, let underlying):
            return "Invalid YAML in \(path): \(underlying.localizedDescription)"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .jsonEncodingFailed(let underlying):
            return "Could not encode JSON: \(underlying.localizedDescription)"
        case .unableToWriteFile(let path, let underlying):
            return "Could not write to \(path): \(underlying.localizedDescription)"
        case .unableToOpenFile(let path, let underlying):
            return "Could not open \(path): \(underlying.localizedDescription)"
        case .mermaidResourceMissing:
            return "Mermaid resource is missing from the app bundle."
        case .invalidStoryboardYAML(let underlying):
            return "Invalid storyboard YAML: \(underlying.localizedDescription)"
        case .unsupportedEventsImport:
            return "Unsupported events YAML shape; expected top-level list or events/cases array."
        }
    }
}
