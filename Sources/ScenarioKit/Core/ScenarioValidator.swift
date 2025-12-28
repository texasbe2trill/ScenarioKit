import Foundation

enum ScenarioValidator {
    static func validate(_ scenario: Scenario) -> [ScenarioIssue] {
        var issues: [ScenarioIssue] = []

        if scenario.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.error("Scenario name is required."))
        }

        if scenario.services.isEmpty {
            issues.append(.error("At least one service is required."))
        }

        var seenNames = Set<String>()
        let definedNames = Set(scenario.services.map { $0.name })

        for service in scenario.services {
            let trimmedName = service.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty {
                issues.append(.error("Service name is required."))
            }

            if !seenNames.insert(service.name).inserted {
                issues.append(.error("Duplicate service name: \(service.name)"))
            }

            guard let dependencies = service.dependsOn else { continue }

            for dependency in dependencies {
                if dependency == service.name {
                    issues.append(.warning("Service '\(service.name)' depends on itself."))
                }

                if !definedNames.contains(dependency) {
                    issues.append(.warning("Service '\(service.name)' depends on undefined service '\(dependency)'."))
                }
            }
        }

        return issues.sorted(by: { $0.severity.sortIndex < $1.severity.sortIndex })
    }
}

struct ScenarioIssue {
    enum Severity {
        case error
        case warning

        var sortIndex: Int {
            switch self {
            case .error: return 0
            case .warning: return 1
            }
        }
    }

    let severity: Severity
    let message: String

    static func error(_ message: String) -> ScenarioIssue {
        ScenarioIssue(severity: .error, message: message)
    }

    static func warning(_ message: String) -> ScenarioIssue {
        ScenarioIssue(severity: .warning, message: message)
    }
}
