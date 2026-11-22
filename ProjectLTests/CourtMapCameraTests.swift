import CoreLocation
import Testing
@testable import ProjectL

struct CourtMapCameraTests {
    @Test func highlightedCourtTakesPriority() {
        let court = CLLocationCoordinate2D(latitude: 37, longitude: -122)
        let player = CLLocationCoordinate2D(latitude: 38, longitude: -121)

        let target = CourtMapCameraTarget.resolve(highlightedCourt: court, userLocation: player)

        #expect(target?.latitude == court.latitude)
        #expect(target?.longitude == court.longitude)
        #expect(target?.spanMeters == 1_600)
    }

    @Test func userLocationCentersNearbyCourts() {
        let player = CLLocationCoordinate2D(latitude: 38, longitude: -121)

        let target = CourtMapCameraTarget.resolve(highlightedCourt: nil, userLocation: player)

        #expect(target?.latitude == player.latitude)
        #expect(target?.longitude == player.longitude)
        #expect(target?.spanMeters == 10_000)
    }

    @Test func noCoordinatesLeaveCameraTargetUnset() {
        #expect(CourtMapCameraTarget.resolve(highlightedCourt: nil, userLocation: nil) == nil)
    }
}
