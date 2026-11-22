import SwiftUI

struct CourtDetailView: View {
    let court: NearbyCourt
    @Environment(\.isDemoMode) private var isDemoMode
    @ObservedObject var sessionReminderStore: SessionReminderStore


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    if isDemoMode {
                        DemoCourtMapView(courts: SampleData.nearbyCourts, highlightedCourt: court)
                    } else {
                        CourtMapView(courts: [court], userLocation: nil, highlightedCourt: court)
                    }
                }
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(court.name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.inkBrown)
                    Text(court.distanceText(for: .english))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.olive)
                }

                WarmCard {
                    VStack(alignment: .leading, spacing: 15) {
                        DetailRow(
                            icon: "mappin.and.ellipse",
                            title: String(localized: "Address"),
                            value: court.address.isEmpty
                                ? String(localized: "Not provided by Maps")
                                : court.address
                        )
                        DetailRow(
                            icon: "tennis.racket",
                            title: String(localized: "Surface"),
                            value: court.surfaceInformation
                                ?? String(localized: "Not provided by Maps")
                        )
                        DetailRow(
                            icon: "clock",
                            title: String(localized: "Session time"),
                            value: court.sessionTime
                                ?? String(localized: "Check with the venue")
                        )
                    }
                }

                if !isDemoMode {
                    Button {
                        court.openDirections()
                    } label: {
                        Label(
                            String(localized: "Navigate with Apple Maps"),
                            systemImage: "arrow.triangle.turn.up.right.diamond.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(Color.softCream)
                        .background(Color.olive)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                NavigationLink {
                    SessionReminderView(
                        store: sessionReminderStore,
                        initialCourtName: court.name
                    )
                } label: {
                    Label(
                        String(localized: "Set session reminder"),
                        systemImage: "bell.badge"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(Color.olive)
                    .background(Color.oliveSoft.opacity(0.7))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("court-session-reminder-link")
            }
            .padding(20)
        }
        .background { CommunityBackdrop() }
        .navigationTitle(String(localized: "Court details"))
        .navigationBarTitleDisplayMode(.inline)
        .localizedBackButton()
    }
}

private struct DetailRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.olive)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.warmGold)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Color.mutedBrown)
            }
        }
    }
}
