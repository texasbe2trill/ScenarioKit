import Foundation

enum FileLoader {
    static func loadText(atPath path: String) throws -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ScenarioKitError.fileNotFound(path)
        }

        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw ScenarioKitError.unreadableFile(path, underlying: error)
        }
    }
}
