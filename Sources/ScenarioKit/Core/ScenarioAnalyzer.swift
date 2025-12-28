enum ScenarioAnalyzer {
    static func analyze(_ scenario: Scenario) -> AnalysisReport {
        let services = scenario.services.sorted { $0.name < $1.name }

        var dependentsMap: [String: Set<String>] = [:]
        for service in services {
            for dependency in service.dependsOn ?? [] {
                dependentsMap[dependency, default: []].insert(service.name)
            }
        }

        let nodes = services.map { service -> AnalysisReport.ServiceNode in
            let dependsOn = (service.dependsOn ?? []).sorted()
            let dependents = Array(dependentsMap[service.name] ?? []).sorted()

            return AnalysisReport.ServiceNode(
                name: service.name,
                dependsOn: dependsOn,
                dependents: dependents
            )
        }

        return AnalysisReport(
            scenarioName: scenario.name,
            serviceCount: services.count,
            services: nodes
        )
    }
}
