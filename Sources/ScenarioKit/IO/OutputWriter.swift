import Foundation

enum OutputWriter {
    static func write(_ text: String, toPath path: String) throws {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()

        if !directory.path.isEmpty && directory.path != "." {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        guard let data = text.data(using: .utf8) else {
            throw ScenarioKitError.unableToWriteFile(path, underlying: CocoaError(.fileWriteUnknown))
        }

        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw ScenarioKitError.unableToWriteFile(path, underlying: error)
        }
    }
}
