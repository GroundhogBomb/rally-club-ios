import Foundation

struct Court: Identifiable, Hashable {
    let id: UUID
    let name: String
    let country: String
    let city: String
    let address: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
    let sessionTime: String
    let surfaces: [String]
}
