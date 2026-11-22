import CoreLocation
import SwiftUI

// Main entry for nearby court discovery, the court map, and court details.
struct CourtView: View {
    @ObservedObject var sessionReminderStore: SessionReminderStore
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var discovery: CourtDiscoveryModel
    let isDemoMode: Bool

    init(sessionReminderStore: SessionReminderStore, isDemoMode: Bool) {
        self.sessionReminderStore = sessionReminderStore
        self.isDemoMode = isDemoMode
        _discovery = StateObject(wrappedValue: CourtDiscoveryModel(isDemoMode: isDemoMode))
    }

    private var copy: AppCopy { AppCopy() }
    private var hasLocationPermission: Bool {
        discovery.authorizationStatus == .authorizedAlways || discovery.authorizationStatus == .authorizedWhenInUse
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    PageHeader(
                        eyebrow: copy.courtEyebrow,
                        title: copy.courtTab,
                        subtitle: String(localized: "Find a court for your next game.")
                    )

                    if isDemoMode {
                        DemoCourtMapView(courts: discovery.courts)
                            .frame(height: 180)
                        nearbySection
                    } else if hasLocationPermission && discovery.userLocation != nil {
                        CurrentLocationCard(
                        status: discovery.authorizationStatus,
                        location: discovery.userLocation,
                        language: .english
                    )

                        mapSection
                        nearbySection
                    } else {
                        discoveryIntroduction
                    }

                    HomeStartCard(language: .english)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background { CommunityBackdrop() }
            .navigationDestination(for: NearbyCourt.self) { court in
                CourtDetailView(court: court, sessionReminderStore: sessionReminderStore)
            }
            .navigationBarHidden(true)
        }
        .task {
            if discovery.authorizationStatus != .notDetermined {
                discovery.activate()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && discovery.authorizationStatus != .notDetermined {
                discovery.activate()
            }
        }
    }

    private var discoveryIntroduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Color.clear
                .frame(height: 180)
                .overlay {
                    GeometryReader { geometry in
                        Image("CourtPreview")
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Courts near you"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.inkBrown)
                    .accessibilityAddTraits(.isHeader)
                Text(String(localized: "Discover nearby courts for your next practice or pickup game."))
                .font(.subheadline)
                .foregroundStyle(Color.mutedBrown)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                if discovery.authorizationStatus == .denied {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } else {
                    discovery.activate()
                }
            } label: {
                Label(
                    hasLocationPermission && discovery.searchFailed
                        ? String(localized: "Try location again")
                        : discovery.authorizationStatus == .denied
                        ? String(localized: "Open location settings")
                        : String(localized: "Find nearby courts"),
                    systemImage: "location"
                )
            }
            .buttonStyle(AppActionButtonStyle())
            .disabled(discovery.authorizationStatus == .restricted)
            .accessibilityIdentifier("court-location-action")

            if hasLocationPermission {
                HStack(spacing: 8) {
                    if !discovery.searchFailed { ProgressView().tint(Color.olive) }
                    Text(discovery.searchFailed
                        ? String(localized: "Location is unavailable. Please try again.")
                        : String(localized: "Getting your location…"))
                        .font(.footnote)
                        .foregroundStyle(Color.mutedBrown)
                }
            }

            Text(discovery.authorizationStatus == .restricted
                ? String(localized: "Location is restricted on this device. Posts and game requests are still available.")
                : String(localized: "With your permission, location is used to find nearby courts."))
                .font(.caption)
                .foregroundStyle(Color.mutedBrown)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background { WarmCanvas().clipShape(RoundedRectangle(cornerRadius: 14)) }
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.appSeparator, lineWidth: 0.5) }
    }

    @ViewBuilder
    private var mapSection: some View {
        if let location = discovery.userLocation {
            CourtMapView(
                courts: discovery.courts,
                userLocation: location,
                highlightedCourt: nil
            )
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.olive.opacity(0.12), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isDemoMode ? String(localized: "Demo courts") : String(localized: "Nearby courts"))
                    .font(.headline)
                    .foregroundStyle(Color.inkBrown)
                Spacer()
                if discovery.userLocation != nil && !discovery.isSearching {
                    Button {
                        discovery.retry()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Color.olive)
                    }
                    .accessibilityLabel(String(localized: "Search again"))
                }
            }

            if discovery.isSearching {
                WarmCard {
                    HStack(spacing: 12) {
                        ProgressView().tint(Color.olive)
                        Text(String(localized: "Looking for nearby courts…"))
                        .font(.subheadline)
                        .foregroundStyle(Color.mutedBrown)
                    }
                }
            } else if !discovery.courts.isEmpty {
                ForEach(discovery.courts) { court in
                    NearbyCourtCard(court: court, language: .english, isDemoMode: isDemoMode)
                }
            } else {
                EmptyCourtState(
                    status: discovery.authorizationStatus,
                    hasLocation: discovery.userLocation != nil,
                    searchFailed: discovery.searchFailed,
                    language: .english
                )
            }
        }
    }
}

private struct HomeStartCard: View {
    let language: AppLanguage


    var body: some View {
        EditorialSection {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(Color.warmGold)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Share match highlights and find your next game."))
                        .font(.footnote)
                        .foregroundStyle(Color.mutedBrown)
                        .lineSpacing(3)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-start-card")
    }
}

private struct CurrentLocationCard: View {
    let status: CLAuthorizationStatus
    let location: CLLocation?
    let language: AppLanguage


    var body: some View {
        EditorialSection {
            HStack(spacing: 13) {
                Image(systemName: location == nil ? "location.circle" : "location.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.warmGold)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Current location"))
                        .font(.headline)
                        .foregroundStyle(Color.inkBrown)
                    Text(locationText)
                        .font(.subheadline)
                        .foregroundStyle(Color.mutedBrown)
                }
                Spacer()
            }
        }
    }

    private var locationText: String {
        if let location {
            return String(format: "%.4f, %.4f", locale: Locale(identifier: "en_US_POSIX"), location.coordinate.latitude, location.coordinate.longitude)
        }

        switch status {
        case .notDetermined:
            return String(localized: "Location access helps Rally Club find courts nearby.")
        case .denied, .restricted:
            return String(localized: "Location is unavailable. You can still view this page.")
        case .authorizedAlways, .authorizedWhenInUse:
            return String(localized: "Getting your location…")
        @unknown default:
            return String(localized: "Location status unavailable")
        }
    }
}

private struct NearbyCourtCard: View {
    let court: NearbyCourt
    let language: AppLanguage
    let isDemoMode: Bool


    var body: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "tennis.racket")
                        .font(.title3)
                        .foregroundStyle(Color.warmGold)
                        .frame(width: 42, height: 42)
                        .background(Color.warmGold.opacity(0.12))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(court.name)
                            .font(.headline)
                            .foregroundStyle(Color.inkBrown)
                        Label(court.distanceText(for: language), systemImage: "figure.walk")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.olive)
                    }
                    Spacer()
                }

                if !court.address.isEmpty {
                    Text(court.address)
                        .font(.subheadline)
                        .foregroundStyle(Color.mutedBrown)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    NavigationLink(value: court) {
                        Text(String(localized: "View details"))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(Color.olive)
                            .background(Color.oliveSoft.opacity(0.75))
                            .clipShape(Capsule())
                    }

                    if !isDemoMode {
                        Button {
                            court.openDirections()
                        } label: {
                            Label(String(localized: "Directions"), systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(Color.softCream)
                                .background(Color.olive)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct EmptyCourtState: View {
    let status: CLAuthorizationStatus
    let hasLocation: Bool
    let searchFailed: Bool
    let language: AppLanguage


    var body: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: icon).foregroundStyle(Color.inkBrown)
                }
                .font(.headline)
                .foregroundStyle(Color.inkBrown)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.mutedBrown)
                    .lineSpacing(3)
            }
        }
    }

    private var title: String {
        if status == .denied || status == .restricted {
            return String(localized: "Location not enabled")
        }
        if hasLocation && searchFailed {
            return String(localized: "No results right now")
        }
        return String(localized: "Waiting for location")
    }

    private var message: String {
        if status == .denied || status == .restricted {
            return String(localized: "The rest of the app remains available. You can enable location later in Settings.")
        }
        if hasLocation && searchFailed {
            return String(localized: "Apple Maps did not return a matching nearby court. Please try again later.")
        }
        return String(localized: "Nearby courts will appear once location is available.")
    }

    private var icon: String {
        status == .denied || status == .restricted ? "location.slash.fill" : "building.columns"
    }
}
