import Combine
import Foundation
import SwiftUI

// MAINTENANCE-POINT: VERSION-GATE-001
// Optional, memory-only compatibility advice. Failure must never prevent app use.
@MainActor
final class VersionGate: ObservableObject {
    struct Messages: Decodable {
        let en: String?
        enum CodingKeys: String, CodingKey { case en }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            en = values.contains(.en) ? try values.decode(String.self, forKey: .en) : nil
        }
    }

    private struct Configuration: Decodable {
        let schema: Int
        let minimum: String
        let block: Bool
        let messages: Messages
        let update: String
        enum CodingKeys: String, CodingKey {
            case schema, minimum = "minimum_version", block = "block_below_minimum"
            case messages = "message", update = "update_url"
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schema = try values.decode(Int.self, forKey: .schema)
            minimum = try values.decode(String.self, forKey: .minimum)
            block = values.contains(.block) ? try values.decode(Bool.self, forKey: .block) : false
            messages = try values.decode(Messages.self, forKey: .messages)
            update = try values.decode(String.self, forKey: .update)
        }
    }

    struct Notice {
        let messages: Messages
        let updateURL: URL?
        let blocks: Bool
        func message(for _: AppLanguage) -> String {
            if let value = messages.en, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }

            return blocks
                ? String(localized: "Please update the app to continue.")
                : String(localized: "Please update to the latest version.")
        }
    }

    nonisolated static let maximumBytes = 16 * 1024
    @Published private(set) var notice: Notice?
    private var candidate: Notice?
    private var active = false
    private var ready = false
    private var showedSoftNotice = false
    private var generation = 0
    private var requestTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        generation += 1
        candidate = nil
        notice = nil
        presentationTask?.cancel()
        if value { startIfIdle() }
        else { requestTask?.cancel() } // Keep the handle until cancellation actually finishes.
    }

    func setReady(_ value: Bool) {
        ready = value
        presentationTask?.cancel()
        if !value { notice = nil }
        else { presentWhenReady() }
    }

    func dismissSoftNotice() {
        guard notice?.blocks != true else { return }
        notice = nil
    }

    private func startIfIdle() {
        guard active, requestTask == nil else { return }
        let ticket = generation
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        requestTask = Task { [weak self] in
            let data = await Self.read(until: deadline)
            guard let self else { return }
            self.requestTask = nil
            guard !Task.isCancelled, self.active, self.generation == ticket else {
                if self.active { self.startIfIdle() }
                return
            }
            let result = Self.evaluate(data, installedVersion: installed)
            guard ContinuousClock.now < deadline else { return }
            self.candidate = result
            self.presentWhenReady()
        }
    }

    private func presentWhenReady() {
        presentationTask?.cancel()
        guard active, ready, notice == nil, let candidate,
              candidate.blocks || !showedSoftNotice else { return }
        let ticket = generation
        presentationTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return }
            guard let self, !Task.isCancelled, self.active, self.ready,
                  self.generation == ticket, self.notice == nil else { return }
            if !candidate.blocks { self.showedSoftNotice = true }
            self.notice = candidate
        }
    }

    nonisolated static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        func segments(_ value: String) -> [Int]? {
            guard !value.isEmpty, value.utf8.count <= maximumBytes else { return nil }
            var result: [Int] = []
            for part in value.split(separator: ".", omittingEmptySubsequences: false) {
                guard !part.isEmpty, part.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                      let number = Int(part) else { return nil }
                result.append(number)
            }
            return result
        }
        guard let left = segments(lhs), let right = segments(rhs) else { return nil }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    nonisolated static func storeURL(_ value: String) -> URL? {
        guard !value.unicodeScalars.contains(where: {
            CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
        }), let parts = URLComponents(string: value),
              parts.scheme?.lowercased() == "https", parts.host?.lowercased() == "apps.apple.com",
              parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443 else { return nil }
        return parts.url
    }

    nonisolated static func evaluate(_ data: Data?, installedVersion: String?) -> Notice? {
        guard let data, data.count <= maximumBytes, let installedVersion,
              let config = try? JSONDecoder().decode(Configuration.self, from: data), config.schema == 1,
              compare(installedVersion, config.minimum) == .orderedAscending else { return nil }
        let url = storeURL(config.update)
        return Notice(messages: config.messages, updateURL: url, blocks: config.block && url != nil)
    }

    nonisolated private static func read(until deadline: ContinuousClock.Instant) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask { await payload() }
            group.addTask {
                try? await Task.sleep(until: deadline, clock: .continuous)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    nonisolated private static func payload() async -> Data? {
#if DEBUG
        if let flag = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--version-gate-fixture=") }) {
            let mode = String(flag.dropFirst("--version-gate-fixture=".count))
            if mode == "slow" {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return nil }
            }
            return fixture(mode)
        }
#endif
        guard let url = URL(string: "https://example.invalid/projectl/ios-config.json") else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 5)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        return await withTaskCancellationHandler {
            do {
                let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirect())
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      response.expectedContentLength <= Int64(maximumBytes) else { return nil }
                var data = Data()
                for try await byte in bytes {
                    guard !Task.isCancelled, data.count < maximumBytes else { return nil }
                    data.append(byte)
                }
                return Task.isCancelled ? nil : data
            } catch { return nil }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct VersionGateReadyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

struct VersionGatePresentation: ViewModifier {
    @ObservedObject var gate: VersionGate
    @Environment(\.openURL) private var openURL
    private var title: String {
        gate.notice?.blocks == true
            ? String(localized: "Update required")
            : String(localized: "Update available")
    }
    private var updateTitle: String { String(localized: "Update") }

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(gate.notice?.blocks == true)
                .accessibilityHidden(gate.notice?.blocks == true)
            if let notice = gate.notice, notice.blocks {
                VStack {
                    WarmCard {
                        VStack(spacing: 14) {
                            Image(systemName: "arrow.down.app")
                                .font(.title2).foregroundStyle(Color.olive)
                            Text(verbatim: title).font(.headline).foregroundStyle(Color.inkBrown)
                            Text(verbatim: notice.message(for: .english))
                                .font(.subheadline).foregroundStyle(Color.mutedBrown)
                                .multilineTextAlignment(.center)
                            if let url = notice.updateURL {
                                Button(updateTitle) { openURL(url) }
                                    .buttonStyle(AppActionButtonStyle())
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { CommunityBackdrop() }
                .accessibilityAddTraits(.isModal)
            }
        }
        .alert(title, isPresented: Binding(
            get: { gate.notice != nil && gate.notice?.blocks == false },
            set: { if !$0 { gate.dismissSoftNotice() } }
        )) {
            if let url = gate.notice?.updateURL {
                Button(updateTitle) { openURL(url); gate.dismissSoftNotice() }
            }
            Button(String(localized: "Not now"), role: .cancel) { gate.dismissSoftNotice() }
        } message: {
            Text(verbatim: gate.notice?.message(for: .english) ?? "")
        }
    }
}

#if DEBUG
extension VersionGate {
    nonisolated private static func sample(block: Bool = false, url: String = "https://apps.apple.com/app/id0000000000") -> [String: Any] {
        ["schema": 1, "minimum_version": "999.0", "block_below_minimum": block,
         "message": ["en": "Fixture update notice"], "update_url": url]
    }

    nonisolated private static func fixture(_ mode: String) -> Data? {
        if mode == "bad" { return Data("{invalid-json".utf8) }
        guard mode == "soft" || mode == "block" || mode == "slow" else { return nil }
        return try? JSONSerialization.data(withJSONObject: sample(block: mode == "block"))
    }

    static func runContractChecks() {
        do {
            func data(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
            func check(_ value: Bool) { precondition(value) }
            func decision(_ object: [String: Any], version: String? = "1.0") throws -> Notice? {
                evaluate(try data(object), installedVersion: version)
            }
            precondition(compare("1.10", "1.9") == .orderedDescending)
            precondition(compare("1.0", "1.0.0") == .orderedSame)
            precondition(compare("0.9", "1") == .orderedAscending)
            for invalid in ["", "1..0", ".1", "1.", "1.0-beta", "-1", "1e3", " 1", "１.０", String(repeating: "9", count: 100)] {
                precondition(compare(invalid, "1") == nil && compare("1", invalid) == nil)
            }
            precondition(storeURL("https://apps.apple.com/app/id1") != nil)
            precondition(storeURL("HTTPS://APPS.APPLE.COM:443/app/id1") != nil)
            for invalid in ["", "http://apps.apple.com/app/id1", "https://apps.apple.com.evil.invalid/app/id1",
                "https://evil.invalid/?apps.apple.com", "https://user@apps.apple.com/app/id1", "https://apps.apple.com:444/app/id1",
                "https://apps.apple.com./app/id1", "javascript:alert(1)", " https://apps.apple.com/app/id1", "https://apps.apple.com/\napp/id1"] {
                precondition(storeURL(invalid) == nil)
            }
            precondition(evaluate(nil, installedVersion: "1") == nil)
            for invalid in [Data(), Data("{broken".utf8), Data("[]".utf8), Data("null".utf8)] {
                precondition(evaluate(invalid, installedVersion: "1") == nil)
            }
            var oversized = try data(sample())
            oversized.append(Data(repeating: 32, count: maximumBytes + 1 - oversized.count))
            precondition(evaluate(oversized, installedVersion: "1") == nil)
            oversized.removeLast()
            precondition(evaluate(oversized, installedVersion: "1") != nil)
            for key in ["schema", "minimum_version", "message", "update_url"] {
                var missing = sample(); missing.removeValue(forKey: key)
                check(try decision(missing) == nil)
            }
            for (key, value) in [("schema", "1" as Any), ("schema", true), ("schema", 2), ("schema", 1.5),
                ("minimum_version", 2), ("minimum_version", "broken"), ("minimum_version", String(repeating: "9", count: 100)),
                ("block_below_minimum", "true"), ("block_below_minimum", NSNull()),
                ("message", "text"), ("message", ["en": 4]), ("update_url", 4)] {
                var invalid = sample(); invalid[key] = value
                check(try decision(invalid) == nil)
            }
            check(try decision(sample(), version: nil) == nil)
            check(try decision(sample(), version: "invalid") == nil)
            check(try decision(sample(), version: "999.0.0") == nil)
            check(try decision(sample(), version: "1000") == nil)
            check(try decision(sample())?.blocks == false)
            check(try decision(sample())?.message(for: .english) == "Fixture update notice")
            check(try decision(sample(block: true))?.blocks == true)
            let downgraded = try decision(sample(block: true, url: "https://example.invalid/update"))
            precondition(downgraded?.blocks == false && downgraded?.updateURL == nil)
            var defaults = sample(); defaults.removeValue(forKey: "block_below_minimum")
            defaults["message"] = ["future": ["unknown": true]]
            defaults["future"] = ["unknown": true]
            let fallback = try decision(defaults)
            precondition(fallback?.blocks == false)
            precondition(fallback?.message(for: .english) == "Please update to the latest version.")
            print("VERSION-GATE-001 passed")
        } catch {
            preconditionFailure("VERSION-GATE-001 unexpected fixture error")
        }
    }
}
#endif
