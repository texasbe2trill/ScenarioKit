struct AnalysisReport: Codable {
    struct ServiceNode: Codable {
        let name: String
        let dependsOn: [String]
        let dependents: [String]
    }

    let scenarioName: String
    let serviceCount: Int
    let services: [ServiceNode]
}
