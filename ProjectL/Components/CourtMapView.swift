import MapKit
import SwiftUI

// MAINTENANCE-POINT: COURT-MAP-001
struct CourtMapView: View {
    let courts: [NearbyCourt]
    let userLocation: CLLocation?
    let highlightedCourt: NearbyCourt?

    @State private var position: MapCameraPosition = .automatic
    @State private var lastTarget: CourtMapCameraTarget?
    @State private var selectedCourtID: NearbyCourt.ID?

    private var cameraTarget: CourtMapCameraTarget? {
        CourtMapCameraTarget.resolve(
            highlightedCourt: highlightedCourt?.coordinate,
            userLocation: userLocation?.coordinate
        )
    }

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .rotate], selection: $selectedCourtID) {
            UserAnnotation()

            ForEach(courts) { court in
                Annotation(court.name, coordinate: court.coordinate, anchor: .bottom) {
                    courtMarker(court)
                }
                .tag(court.id)
                .annotationTitles(selectedCourtID == court.id ? .hidden : .automatic)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("court-map")
        .onChange(of: cameraTarget, initial: true) { _, target in
            guard let target else { return }
            if let lastTarget {
                // Small location updates should not interrupt a person panning the map.
                guard lastTarget.spanMeters != target.spanMeters
                    || lastTarget.location.distance(from: target.location) > 100 else { return }
                withAnimation { position = .region(target.region) }
            } else {
                position = .region(target.region)
            }
            lastTarget = target
        }
    }

    private func courtMarker(_ court: NearbyCourt) -> some View {
        VStack(spacing: 4) {
            if selectedCourtID == court.id {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: court.name)
                        .font(.subheadline.weight(.semibold))
                    if !court.address.isEmpty {
                        Text(verbatim: court.address)
                            .font(.caption)
                    }
                }
                .foregroundStyle(Color.inkBrown)
                .padding(9)
                .background(Color.softCream, in: RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2, y: 1)
                .frame(maxWidth: 240)
                .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                selectedCourtID = court.id
            } label: {
                Image(systemName: "tennis.racket")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.olive, in: Circle())
                    .background(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.olive)
                            .frame(width: 10, height: 10)
                            .rotationEffect(.degrees(45))
                            .offset(y: 3)
                    }
                    .padding(.bottom, 6)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: court.name))
            .accessibilityIdentifier("court-map-marker-\(court.id)")
        }
    }
}

struct CourtMapCameraTarget: Equatable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let spanMeters: CLLocationDistance

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: spanMeters,
            longitudinalMeters: spanMeters
        )
    }

    static func resolve(
        highlightedCourt: CLLocationCoordinate2D?,
        userLocation: CLLocationCoordinate2D?
    ) -> Self? {
        guard let center = highlightedCourt ?? userLocation else { return nil }
        return Self(latitude: center.latitude, longitude: center.longitude,
                    spanMeters: highlightedCourt == nil ? 10_000 : 1_600)
    }
}

// Fictional locations on an offline map. No map provider is used in the demo.
struct DemoCourtMapView: View {
    let courts: [NearbyCourt]
    var highlightedCourt: NearbyCourt?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.oliveSoft
                Path { path in
                    let size = geometry.size
                    path.move(to: CGPoint(x: 0, y: size.height * 0.68))
                    path.addLine(to: CGPoint(x: size.width, y: size.height * 0.42))
                    path.move(to: CGPoint(x: size.width * 0.44, y: 0))
                    path.addLine(to: CGPoint(x: size.width * 0.62, y: size.height))
                }
                .stroke(Color.softCream, lineWidth: 9)
                .accessibilityHidden(true)

                Text(String(localized: "Bayridge · Demo map"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.inkBrown)
                    .padding(12)

                ForEach(courts) { court in
                    Group {
                        if let highlightedCourt {
                            pin(court, highlighted: court.id == highlightedCourt.id)
                        } else {
                            NavigationLink(value: court) { pin(court, highlighted: false) }
                                .buttonStyle(.plain)
                        }
                    }
                    .position(
                        x: geometry.size.width * (0.5 + court.longitude * 45),
                        y: geometry.size.height * (0.55 - court.latitude * 30)
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func pin(_ court: NearbyCourt, highlighted: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
            Text(court.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(highlighted ? Color.softCream : Color.inkBrown)
        .padding(7)
        .background(highlighted ? Color.olive : Color.softCream, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
