import Foundation

enum SampleData {
    static let courts: [Court] = [
        Court(
            id: UUID(),
            name: "Northbank Courts",
            country: "Demo district",
            city: "Bayridge",
            address: "Northbank Park",
            latitude: 0.004, longitude: -0.004, distanceMeters: 650,
            sessionTime: "Saturday 9:00 AM",
            surfaces: ["Outdoor hard court"]
        ),
        Court(
            id: UUID(),
            name: "Cedar Lane Courts",
            country: "Demo district",
            city: "Bayridge",
            address: "Cedar Lane Recreation Loop",
            latitude: -0.004, longitude: 0.004, distanceMeters: 1_200,
            sessionTime: "Wednesday 6:30 PM",
            surfaces: ["Indoor synthetic court"]
        )
    ]

    static let clubAnnouncement = ClubAnnouncement(
        id: 1,
        bodyZH: "",
        bodyEN: "Welcome to Rally Club. Beginner practice is at Northbank Courts every Saturday at 9 AM.",
        bodyJA: "",
        revision: 1,
        updatedAt: "2026-11-22T00:00:00Z"
    )

    static let nearbyCourts = courts.map { court in
        NearbyCourt(
            id: court.name,
            name: court.name,
            address: court.address,
            latitude: court.latitude,
            longitude: court.longitude,
            distanceMeters: court.distanceMeters,
            surfaceInformation: court.surfaces.first,
            sessionTime: court.sessionTime
        )
    }

    static func gameRequests(now: Date = Date()) -> [GameRequest] {
        let firstID = UUID(uuid: (0x1f, 0x7b, 0x7c, 0x62, 0xd1, 0x89, 0x52, 0xd4, 0xb0, 0x45, 0x87, 0xcc, 0x16, 0x2b, 0x3c, 0xff))
        let secondID = UUID(uuid: (0x43, 0x7d, 0x57, 0xf9, 0x55, 0x43, 0x57, 0xe1, 0x9f, 0x35, 0x75, 0xfe, 0x25, 0xa0, 0x74, 0x54))
        let thirdID = UUID(uuid: (0xd5, 0x10, 0x8f, 0x41, 0x14, 0xc1, 0x54, 0xc5, 0xaa, 0x3d, 0xac, 0x29, 0x45, 0xae, 0x1c, 0xaa))

        return [
            GameRequest(
                id: firstID,
                ownerID: CommunityDirectory.demoMember.id,
                isAnonymous: false,
                anonymousIdentity: .playerA,
                title: "One more for Saturday doubles",
                body: "Northbank Courts, Saturday at 9 AM. We need one more player. All levels welcome.",
                createdAt: now.addingTimeInterval(-2_400),
                updatedAt: now.addingTimeInterval(-2_400),
                visibility: .publicContent,
                languageCode: .english,
                responseCount: 12
            ),
            GameRequest(
                id: secondID,
                ownerID: CommunityDirectory.aki.id,
                isAnonymous: true,
                anonymousIdentity: .playerB,
                title: "Thursday rally practice",
                body: "Anyone up for rally drills at Cedar Lane on Thursday evening?",
                createdAt: now.addingTimeInterval(-8_100),
                updatedAt: now.addingTimeInterval(-8_100),
                visibility: .publicContent,
                languageCode: .english,
                responseCount: 7
            ),
            GameRequest(
                id: thirdID,
                ownerID: CommunityDirectory.riley.id,
                isAnonymous: false,
                anonymousIdentity: .playerA,
                title: "One more for Friday doubles",
                body: "We have a court at Cedar Lane at 6:30 PM. Looking for an intermediate player to make four.",
                createdAt: now.addingTimeInterval(-20_000),
                updatedAt: now.addingTimeInterval(-20_000),
                visibility: .publicContent,
                languageCode: .english,
                responseCount: 18
            )
        ]
    }
}
