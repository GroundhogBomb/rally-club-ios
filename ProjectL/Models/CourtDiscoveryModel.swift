import Combine
import CoreLocation
import Foundation
import MapKit

// MAINTENANCE-POINT: COURT-DISCOVERY-001
final class CourtDiscoveryModel: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var userLocation: CLLocation?
    @Published private(set) var courts: [NearbyCourt] = []
    @Published private(set) var isSearching = false
    @Published private(set) var searchFailed = false

    private let locationManager: CLLocationManager?
    private var searchTask: Task<Void, Never>?
    private var activeSearch: MKLocalSearch?
    private var isLocating = false
    private var resultCache: [String: (date: Date, courts: [NearbyCourt])] = [:]

    init(isDemoMode: Bool) {
        let manager = isDemoMode ? nil : CLLocationManager()
        locationManager = manager
        authorizationStatus = manager?.authorizationStatus ?? .notDetermined
        super.init()
        if isDemoMode {
            courts = SampleData.nearbyCourts
        } else {
            manager?.delegate = self
            manager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }
    }

    deinit {
        searchTask?.cancel()
    }

    func activate() {
        guard let locationManager else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            authorizationStatus = .denied
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestCurrentLocation()
        case .denied, .restricted:
            authorizationStatus = locationManager.authorizationStatus
        @unknown default:
            authorizationStatus = locationManager.authorizationStatus
        }
    }

    func retry() {
        guard let userLocation else {
            requestCurrentLocation()
            return
        }
        beginSearch(around: userLocation, useCache: false)
    }

    private func requestCurrentLocation() {
        guard let locationManager, !isLocating else { return }
        isLocating = true
        searchFailed = false
        locationManager.requestLocation()
    }

    private func beginSearch(around location: CLLocation, useCache: Bool = true) {
        searchTask?.cancel()
        activeSearch?.cancel()
        let key = "\(location.coordinate.latitude.rounded(toPlaces: 3))|\(location.coordinate.longitude.rounded(toPlaces: 3))"
        if useCache, let cached = resultCache[key], cached.date > Date().addingTimeInterval(-300) {
            courts = cached.courts
            isSearching = false
            searchFailed = false
            return
        }
        isSearching = true
        searchFailed = false

        searchTask = Task { [weak self] in
            guard let self else { return }
            let results = await self.searchCourts(around: location)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.courts = results
                self.isSearching = false
                self.searchFailed = results.isEmpty
                if !results.isEmpty {
                    self.resultCache = self.resultCache.filter { $0.value.date > Date().addingTimeInterval(-300) }
                    if self.resultCache.count >= 8 { self.resultCache.removeAll() }
                    self.resultCache[key] = (Date(), results)
                }
            }
        }
    }

    private func searchCourts(around location: CLLocation) async -> [NearbyCourt] {
        let queries = ["Tennis court", "Pickleball court", "Basketball court", "Badminton court"]

        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 12_000,
            longitudinalMeters: 12_000
        )
        var uniqueResults: [String: NearbyCourt] = [:]

        for query in queries {
            guard !Task.isCancelled else { break }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = region
            request.resultTypes = .pointOfInterest

            do {
                let search = MKLocalSearch(request: request)
                activeSearch = search
                let timeout = Task {
                    do { try await Task.sleep(for: .seconds(12)); search.cancel() } catch {}
                }
                defer { timeout.cancel() }
                let response = try await search.start()
                guard !Task.isCancelled else { return [] }
                for item in response.mapItems {
                    guard let court = makeCourt(from: item, userLocation: location),
                          isCourt(item, named: court.name) else { continue }

                    if let existing = uniqueResults[court.id] {
                        if court.distanceMeters < existing.distanceMeters {
                            uniqueResults[court.id] = court
                        }
                    } else {
                        uniqueResults[court.id] = court
                    }
                }
            } catch {
                continue
            }
        }

        return uniqueResults.values
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .prefix(20)
            .map { $0 }
    }

    private func makeCourt(
        from item: MKMapItem,
        userLocation: CLLocation
    ) -> NearbyCourt? {
        guard let rawName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else { return nil }

        let coordinate: CLLocationCoordinate2D
        let address: String

        if #available(iOS 26.0, *) {
            coordinate = item.location.coordinate
            let shortAddress = item.address?.shortAddress?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let shortAddress, shortAddress.count >= 8 {
                address = shortAddress
            } else {
                address = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
                    ?? item.address?.fullAddress
                    ?? shortAddress
                    ?? ""
            }
        } else {
            coordinate = item.placemark.coordinate
            address = item.placemark.title ?? ""
        }

        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        let name = rawName
        let displayAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let distance = userLocation.distance(from: destination)
        let normalizedID = "\(name.lowercased())|\(coordinate.latitude.rounded(toPlaces: 4))|\(coordinate.longitude.rounded(toPlaces: 4))"

        return NearbyCourt(
            id: normalizedID,
            name: name,
            address: displayAddress,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            distanceMeters: distance,
            surfaceInformation: nil,
            sessionTime: nil
        )
    }

    private func isCourt(_ item: MKMapItem, named name: String) -> Bool {
        if #available(iOS 18.0, *),
           item.pointOfInterestCategory == .tennis || item.pointOfInterestCategory == .basketball {
            return true
        }
        let courtTerms = ["court", "tennis", "pickleball", "basketball", "badminton", "padel", "racquet", "球場", "球场", "コート"]
        return courtTerms.contains { name.localizedCaseInsensitiveContains($0) }
    }

}

extension CLLocationDegrees {
    fileprivate func rounded(toPlaces places: Int) -> CLLocationDegrees {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

extension CourtDiscoveryModel: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestCurrentLocation()
        case .denied, .restricted:
            searchTask?.cancel()
            activeSearch?.cancel()
            isLocating = false
            resultCache.removeAll()
            courts = []
            isSearching = false
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        isLocating = false
        guard let location = locations.last else { return }
        userLocation = location
        beginSearch(around: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        isSearching = false
        searchFailed = true
    }
}
