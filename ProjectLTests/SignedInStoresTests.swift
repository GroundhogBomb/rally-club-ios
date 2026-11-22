import SwiftUI
import Testing
import UIKit
@testable import ProjectL

@MainActor
struct SignedInStoresTests {
    @Test func rebuildingParentKeepsOneSetOfStoresPerSession() {
        let session = AppSession(configuration: nil)
        var builds = 0

        func makeStores() -> SignedInStores<InMemoryAppDataRepository> {
            builds += 1
            return SignedInStores(repository: InMemoryAppDataRepository(), userID: CommunityDirectory.demoMember.id)
        }

        func root(sessionID: Int) -> some View {
            SignedInTabView(session: session, stores: makeStores())
                .id(sessionID)
        }

        let host = UIHostingController(rootView: root(sessionID: 1))
        #expect(builds == 0)
        host.loadViewIfNeeded()
        _ = host.sizeThatFits(in: CGSize(width: 402, height: 874))
        #expect(builds == 1)

        for _ in 0..<3 {
            host.rootView = root(sessionID: 1)
            _ = host.sizeThatFits(in: CGSize(width: 402, height: 874))
        }
        #expect(builds == 1)

        host.rootView = root(sessionID: 2)
        _ = host.sizeThatFits(in: CGSize(width: 402, height: 874))
        #expect(builds == 2)
    }
}
