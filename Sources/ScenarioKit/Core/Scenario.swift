import Foundation

struct Scenario: Decodable {
    let name: String
    let description: String?
    let services: [Service]

    struct Service: Decodable {
        let name: String
        let dependsOn: [String]?

        enum CodingKeys: String, CodingKey {
            case name
            case dependsOn = "depends_on"
        }
    }
}
