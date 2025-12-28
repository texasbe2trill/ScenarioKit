import Foundation

enum ReportRenderer {
    static func mermaidGraph(for report: AnalysisReport) -> String {
        var lines: [String] = ["graph TD"]
        let services = report.services.sorted { $0.name < $1.name }
        let ids = Dictionary(uniqueKeysWithValues: services.map { ($0.name, sanitizeID($0.name)) })

        for service in services {
            if let id = ids[service.name] {
                lines.append("  \(id)[\"\(escapeLabel(service.name))\"]")
            }
        }

        var edges: [String] = []
        for service in services {
            guard let fromId = ids[service.name] else { continue }
            for dependency in service.dependsOn.sorted() {
                guard let toId = ids[dependency] else { continue }
                edges.append("  \(fromId) --> \(toId)")
            }
        }

        lines.append(contentsOf: edges.sorted())
        return lines.joined(separator: "\n")
    }

    struct ReportSummary: Codable {
        let topDependencies: [RankedService]
        let topDependents: [RankedService]
    }

    struct RankedService: Codable {
        let name: String
        let count: Int
    }

    static func summary(for report: AnalysisReport) -> ReportSummary {
        let services = report.services
        return ReportSummary(
            topDependencies: rank(services: services, keyPath: \.dependsOn),
            topDependents: rank(services: services, keyPath: \.dependents)
        )
    }

    private static func rank(services: [AnalysisReport.ServiceNode], keyPath: KeyPath<AnalysisReport.ServiceNode, [String]>) -> [RankedService] {
        services
            .map { RankedService(name: $0.name, count: $0[keyPath: keyPath].count) }
            .sorted {
                if $0.count == $1.count { return $0.name < $1.name }
                return $0.count > $1.count
            }
            .prefix(5)
            .map { $0 }
    }

    private static func sanitizeID(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let clean = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.reduce(into: "") { $0.append($1) }
        return "svc_\(clean)"
    }

    private static func escapeLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
