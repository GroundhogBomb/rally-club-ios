import CoreLocation
import Foundation
import MapKit

struct NearbyCourt: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let distanceMeters: CLLocationDistance
    let surfaceInformation: String?
    let sessionTime: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distanceText(for language: AppLanguage) -> String {
        if distanceMeters < 1_000 {
            return "\(Int(distanceMeters.rounded())) m"
        }

        let locale = Locale(identifier: language.localeIdentifier)
        return String(format: "%.1f km", locale: locale, distanceMeters / 1_000)
    }

    func openDirections() {
        let destination: MKMapItem
        let location = CLLocation(latitude: latitude, longitude: longitude)

        if #available(iOS 26.0, *) {
            destination = MKMapItem(location: location, address: nil)
        } else {
            destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        }

        destination.name = name
        destination.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
        ])
    }
}
