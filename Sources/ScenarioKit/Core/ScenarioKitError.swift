import Foundation

enum ScenarioKitError: LocalizedError {
    case fileNotFound(String)
    case unreadableFile(String, underlying: Error)
    case invalidYAML(String, underlying: Error)
    case validationFailed(String)
    case jsonEncodingFailed(underlying: Error)

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
        }
    }
}
