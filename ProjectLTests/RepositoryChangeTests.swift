import Observation
import Testing
@testable import ProjectL

@MainActor
struct RepositoryChangeTests {
    @Test(.timeLimit(.minutes(1)))
    func broadcastsToIndependentSubscribersAndRemovesCanceledSubscriber() async throws {
        let broadcaster = RepositoryChangeBroadcaster()
        let first = broadcaster.subscribe()
        let second = broadcaster.subscribe()
        let (firstSignals, firstSignal) = AsyncStream<Void>.makeStream()
        let firstSubscriber = Task {
            for await _ in first { firstSignal.yield() }
        }
        defer { firstSubscriber.cancel() }

        #expect(broadcaster.subscriberCount == 2)
        // Both streams already exist when the producer publishes, even before iteration starts.
        broadcaster.send()
        broadcaster.send()

        var firstIterator = firstSignals.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()
        #expect(await firstIterator.next() != nil)
        #expect(await secondIterator.next() != nil)

        firstSubscriber.cancel()
        await firstSubscriber.value
        let deadline = ContinuousClock.now + .seconds(2)
        while broadcaster.subscriberCount == 2 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(broadcaster.subscriberCount == 1)

        broadcaster.send()
        #expect(await secondIterator.next() != nil)
    }

    private enum Store: Hashable {
        case feed, gameRequests, profile
    }

    @Test(.timeLimit(.minutes(1)))
    func oneRepositoryChangeUpdatesAllThreeStores() async throws {
        let repository = InMemoryAppDataRepository()
        let userID = CommunityDirectory.demoMember.id
        let feed = ClubFeedStore(repository: repository, userID: userID)
        let gameRequests = GameRequestStore(repository: repository, userID: userID)
        let profile = ProfileStore(repository: repository, userID: userID)
        let nickname = "Northbank player"
        #expect(feed.currentUser.nickname != nickname)
        #expect(gameRequests.currentUser.nickname != nickname)
        #expect(profile.nickname != nickname)

        let (signals, signal) = AsyncStream<Store>.makeStream()
        _ = withObservationTracking {
            feed.currentUser.nickname
        } onChange: {
            signal.yield(.feed)
        }
        _ = withObservationTracking {
            gameRequests.currentUser.nickname
        } onChange: {
            signal.yield(.gameRequests)
        }
        _ = withObservationTracking {
            profile.nickname
        } onChange: {
            signal.yield(.profile)
        }

        let updated = repository.updateProfile(
            userID: userID,
            requesterID: userID,
            nickname: nickname,
            signature: nil,
            avatarData: nil,
            matchMomentsPublic: nil,
            displayIdentity: nil
        )
        try #require(updated)

        var received: Set<Store> = []
        var iterator = signals.makeAsyncIterator()
        for _ in 0..<3 {
            if let store = await iterator.next() { received.insert(store) }
        }
        #expect(received == [.feed, .gameRequests, .profile])
        #expect(feed.currentUser.nickname == nickname)
        #expect(gameRequests.currentUser.nickname == nickname)
        #expect(profile.nickname == nickname)
    }
}
