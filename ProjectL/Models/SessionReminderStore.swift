import Combine
import Foundation
import UserNotifications

enum SessionWeekday: Int, CaseIterable, Codable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .sunday: String(localized: "Sunday")
        case .monday: String(localized: "Monday")
        case .tuesday: String(localized: "Tuesday")
        case .wednesday: String(localized: "Wednesday")
        case .thursday: String(localized: "Thursday")
        case .friday: String(localized: "Friday")
        case .saturday: String(localized: "Saturday")
        }
    }
}

struct SessionReminder: Codable, Identifiable, Equatable {
    let id: UUID
    var courtName: String
    var weekday: SessionWeekday
    var hour: Int
    var minute: Int
    var isEnabled: Bool
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, courtName, weekday, hour, minute, isEnabled, createdAt
    }

    init(id: UUID, courtName: String, weekday: SessionWeekday, hour: Int,
         minute: Int, isEnabled: Bool, createdAt: Date) {
        self.id = id
        self.courtName = courtName
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Stable identity and schedule stay required; additive fields must use defaults.
        id = try values.decode(UUID.self, forKey: .id)
        courtName = try values.decode(String.self, forKey: .courtName)
        weekday = try values.decode(SessionWeekday.self, forKey: .weekday)
        hour = try values.decode(Int.self, forKey: .hour)
        minute = try values.decode(Int.self, forKey: .minute)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    var notificationIdentifier: String {
        "session-reminder-\(id.uuidString)"
    }

    func timeText(for language: AppLanguage) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let date = Calendar(identifier: .gregorian).date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct SessionReminderArchive: Decodable {
    var reminders: [SessionReminder] = []
    var hasInvalidRecords = false

    init(from decoder: Decoder) throws {
        var records = try decoder.unkeyedContainer()
        while !records.isAtEnd {
            // superDecoder consumes exactly one element even when its contents are invalid.
            let record = try records.superDecoder()
            do {
                reminders.append(try SessionReminder(from: record))
            } catch {
                hasInvalidRecords = true
            }
        }
    }
}

enum SessionReminderError: Equatable {
    case permissionDenied
    case schedulingFailed
}

enum SessionReminderStorage {
    struct Keys {
        let main: String
        let backup: String
    }

    static func keys(ownerID: UUID) -> Keys {
        let main = "session-reminders.v1.\(ownerID.uuidString)"
        return Keys(main: main, backup: "\(main).unreadable-backup")
    }

    static func clear(ownerID: UUID, defaults: UserDefaults = .standard) {
        let keys = keys(ownerID: ownerID)
        defaults.removeObject(forKey: keys.main)
        defaults.removeObject(forKey: keys.backup)
    }
}

// MAINTENANCE-POINT: SESSION-REMINDER-001
// Store for weekly session reminders, permissions, and scheduling.
@MainActor
final class SessionReminderStore: ObservableObject {
    @Published private(set) var reminders: [SessionReminder] = []
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isUpdating = false
    @Published private(set) var lastError: SessionReminderError?

    private let defaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter
    private let storageKeys: SessionReminderStorage.Keys
    private var storageKey: String { storageKeys.main }
    private var canSaveReminders = false
    private var preservedReminderData: Data?
#if DEBUG
    private var contractNotificationIDs: Set<String>?
#endif

    init(
        ownerID: UUID,
        defaults: UserDefaults = .standard,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        storageKeys = SessionReminderStorage.keys(ownerID: ownerID)
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        loadReminders()

        Task { [weak self] in
            await self?.refreshAuthorizationStatus()
            await self?.restoreScheduledReminders(language: .english)
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func restoreScheduledReminders(language: AppLanguage) async {
        guard authorizationStatus == .authorized
                || authorizationStatus == .provisional
                || authorizationStatus == .ephemeral else { return }

        for reminder in reminders where reminder.isEnabled {
            do {
                try await schedule(reminder, language: language)
            } catch {
                lastError = .schedulingFailed
                return
            }
        }
    }

    func cancelAllScheduledNotifications() {
        cancelNotifications(
            withIdentifiers: reminders.map(\.notificationIdentifier)
        )
    }

    func requestAuthorization() async -> Bool {
        lastError = nil
        isUpdating = true
        defer { isUpdating = false }

        do {
            let granted = try await requestAuthorizationFromCenter()
            await refreshAuthorizationStatus()
            if !granted {
                lastError = .permissionDenied
            }
            return granted
        } catch {
            lastError = .permissionDenied
            return false
        }
    }

    func addReminder(
        courtName: String,
        weekday: SessionWeekday,
        hour: Int,
        minute: Int,
        language: AppLanguage
    ) async -> Bool {
        guard ensureWritableStorage() else { return false }
        let trimmedName = courtName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        guard await ensurePermission() else { return false }

        lastError = nil
        isUpdating = true
        defer { isUpdating = false }

        let reminder = SessionReminder(
            id: UUID(),
            courtName: trimmedName,
            weekday: weekday,
            hour: min(max(hour, 0), 23),
            minute: min(max(minute, 0), 59),
            isEnabled: true,
            createdAt: Date()
        )

        do {
            try await schedule(reminder, language: language)
            reminders.append(reminder)
            sortReminders()
            saveReminders()
            return true
        } catch {
            lastError = .schedulingFailed
            return false
        }
    }

    func updateReminder(
        id: UUID,
        courtName: String,
        weekday: SessionWeekday,
        hour: Int,
        minute: Int,
        language: AppLanguage
    ) async -> Bool {
        guard ensureWritableStorage() else { return false }
        let trimmedName = courtName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = reminders.firstIndex(where: { $0.id == id })
        else { return false }

        var updatedReminder = reminders[index]
        updatedReminder.courtName = trimmedName
        updatedReminder.weekday = weekday
        updatedReminder.hour = min(max(hour, 0), 23)
        updatedReminder.minute = min(max(minute, 0), 59)

        if updatedReminder.isEnabled {
            guard await ensurePermission() else { return false }
            lastError = nil
            isUpdating = true
            defer { isUpdating = false }

            do {
                try await schedule(updatedReminder, language: language)
                reminders[index] = updatedReminder
                sortReminders()
                saveReminders()
                return true
            } catch {
                lastError = .schedulingFailed
                return false
            }
        }

        cancelNotifications(
            withIdentifiers: [updatedReminder.notificationIdentifier]
        )
        reminders[index] = updatedReminder
        sortReminders()
        saveReminders()
        return true
    }

    func setEnabled(_ enabled: Bool, for reminderID: UUID, language: AppLanguage) async -> Bool {
        guard ensureWritableStorage() else { return false }
        guard let index = reminders.firstIndex(where: { $0.id == reminderID }) else { return false }

        if enabled {
            guard await ensurePermission() else { return false }
            lastError = nil
            isUpdating = true
            defer { isUpdating = false }

            do {
                var reminder = reminders[index]
                reminder.isEnabled = true
                try await schedule(reminder, language: language)
                reminders[index] = reminder
                saveReminders()
                return true
            } catch {
                lastError = .schedulingFailed
                return false
            }
        }

        cancelNotifications(
            withIdentifiers: [reminders[index].notificationIdentifier]
        )
        reminders[index].isEnabled = false
        saveReminders()
        return true
    }

    func removeReminder(_ reminder: SessionReminder) {
        guard ensureWritableStorage() else { return }
        cancelNotifications(
            withIdentifiers: [reminder.notificationIdentifier]
        )
        reminders.removeAll { $0.id == reminder.id }
        saveReminders()
    }

    func clearError() {
        lastError = nil
    }

    private func ensurePermission() async -> Bool {
#if DEBUG
        if contractNotificationIDs != nil { return true }
#endif
        let settings = await notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await requestAuthorization()
        case .denied:
            lastError = .permissionDenied
            return false
        @unknown default:
            lastError = .permissionDenied
            return false
        }
    }

    private func schedule(_ reminder: SessionReminder, language: AppLanguage) async throws {
#if DEBUG
        if contractNotificationIDs != nil {
            contractNotificationIDs?.insert(reminder.notificationIdentifier)
            return
        }
#endif

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Session reminder")
        content.body = String(localized: "Coming up: \(reminder.courtName)")
        content.sound = .default

        var components = DateComponents()
        components.weekday = reminder.weekday.rawValue
        components.hour = reminder.hour
        components.minute = reminder.minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: reminder.notificationIdentifier,
            content: content,
            trigger: trigger
        )
        cancelNotifications(withIdentifiers: [reminder.notificationIdentifier])
        try await addNotificationRequest(request)
    }

    private func cancelNotifications(withIdentifiers identifiers: [String]) {
#if DEBUG
        if contractNotificationIDs != nil {
            for id in identifiers { contractNotificationIDs?.remove(id) }
            return
        }
#endif
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func loadReminders() {
        guard let data = defaults.data(forKey: storageKey) else {
            canSaveReminders = defaults.object(forKey: storageKey) == nil
            return
        }
        preservedReminderData = data
        canSaveReminders = false
        do {
            let decoded = try JSONDecoder().decode(SessionReminderArchive.self, from: data)
            reminders = decoded.reminders
            sortReminders()
            canSaveReminders = !decoded.hasInvalidRecords || backupUnreadableData(data)
        } catch {
            canSaveReminders = backupUnreadableData(data)
        }
        if canSaveReminders { preservedReminderData = nil }
    }

    private func backupUnreadableData(_ data: Data) -> Bool {
        // Keep the first backup. It is never decoded or used to restore reminders.
        if defaults.object(forKey: storageKeys.backup) != nil { return true }
        defaults.set(data, forKey: storageKeys.backup)
        // UserDefaults.set has no success result; verify bytes before permitting main-key writes.
        return defaults.data(forKey: storageKeys.backup) == data
    }

    private func saveReminders() {
        guard canSaveReminders,
              let data = try? JSONEncoder().encode(reminders) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func ensureWritableStorage() -> Bool {
        guard canSaveReminders else {
            lastError = .schedulingFailed // Existing UI already explains that the reminder was not saved.
            return false
        }
        return true
    }

#if DEBUG
    private init(contractOwnerID: UUID, defaults: UserDefaults) {
        storageKeys = SessionReminderStorage.keys(ownerID: contractOwnerID)
        self.defaults = defaults
        notificationCenter = .current()
        contractNotificationIDs = []
        loadReminders() // No notification reads, requests, scheduling or cancellation in these checks.
    }

    static func runPersistenceContractChecks() async {
        // Frozen V1 fixture: never generate this sample from the current encoder.
        let v1 = #"[{"id":"93498718-1C9D-4A78-9C23-71C3D80D48A1","courtName":"V1 court","weekday":1,"hour":9,"minute":30,"isEnabled":false,"createdAt":750000000}]"#
        let ownerID = UUID(uuidString: "7A5F12C3-8A21-47AC-B214-E7180621B4D0")!
        let suite = "SESSION-REMINDER-001.contract.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let keys = SessionReminderStorage.keys(ownerID: ownerID)
        let key = keys.main

        func load(_ json: String) -> SessionReminderStore {
            defaults.set(Data(json.utf8), forKey: key)
            return SessionReminderStore(contractOwnerID: ownerID, defaults: defaults)
        }
        func checkStored(_ store: SessionReminderStore) {
            assert(try! JSONDecoder().decode([SessionReminder].self,
                from: defaults.data(forKey: key)!) == store.reminders)
        }
        let original = load(v1)
        assert(original.reminders.count == 1)
        let reminder = original.reminders[0]
        assert(reminder.id.uuidString == "93498718-1C9D-4A78-9C23-71C3D80D48A1")
        assert(reminder.courtName == "V1 court" && reminder.weekday == .sunday)
        assert(reminder.hour == 9 && reminder.minute == 30 && !reminder.isEnabled)
        assert(reminder.createdAt == Date(timeIntervalSinceReferenceDate: 750000000))
        original.saveReminders()
        assert(try! JSONDecoder().decode([SessionReminder].self, from: defaults.data(forKey: key)!) == [reminder])

        let unknown = v1.replacingOccurrences(of: #""courtName":"V1 court""#,
            with: #""courtName":"V1 court","futureField":{"version":2,"values":[true,null]}"#)
        assert(load(unknown).reminders == [reminder])
        let missingMetadata = v1.replacingOccurrences(of: ",\"isEnabled\":false,\"createdAt\":750000000", with: "")
        let legacy = load(missingMetadata)
        assert(legacy.reminders.count == 1 && legacy.reminders[0].isEnabled)
        assert(legacy.reminders[0].createdAt == Date(timeIntervalSinceReferenceDate: 0))

        // Invalid records at the start/middle cannot hide valid records later in the array.
        let object = String(v1.dropFirst().dropLast())
        let mixed = "[null,\(object),{\"id\":\"broken\"},\(object)]"
        for damaged in ["{broken-json", "{}", "[null,{}]", mixed] {
            defaults.removeObject(forKey: keys.backup)
            let recovered = load(damaged)
            let bytes = Data(damaged.utf8)
            assert(defaults.data(forKey: keys.backup) == bytes)
            assert(defaults.data(forKey: key) == bytes) // Loading alone does not rewrite the main key.
            assert(recovered.canSaveReminders && recovered.preservedReminderData == nil)
            if damaged == mixed { assert(recovered.reminders == [reminder, reminder]) }
            else { assert(recovered.reminders.isEmpty) }
            let recoveredCount = recovered.reminders.count
            let added = await recovered.addReminder(courtName: "Recovered court", weekday: .monday,
                hour: 10, minute: 15, language: .english)
            assert(added)
            checkStored(recovered)
            let newReminder = recovered.reminders.first { $0.courtName == "Recovered court" }!
            assert(recovered.contractNotificationIDs?.contains(newReminder.notificationIdentifier) == true)
            let updated = await recovered.updateReminder(id: newReminder.id, courtName: "Edited court",
                weekday: .tuesday, hour: 11, minute: 20, language: .english)
            assert(updated && recovered.reminders.first { $0.id == newReminder.id }?.courtName == "Edited court")
            checkStored(recovered)
            let disabled = await recovered.setEnabled(false, for: newReminder.id, language: .english)
            assert(disabled && recovered.contractNotificationIDs?.isEmpty == true)
            assert(recovered.reminders.first { $0.id == newReminder.id }?.isEnabled == false)
            checkStored(recovered)
            let enabled = await recovered.setEnabled(true, for: newReminder.id, language: .english)
            assert(enabled && recovered.contractNotificationIDs?.contains(newReminder.notificationIdentifier) == true)
            recovered.removeReminder(newReminder)
            assert(recovered.reminders.count == recoveredCount)
            assert(recovered.contractNotificationIDs?.isEmpty == true)
            checkStored(recovered)
            assert(defaults.data(forKey: keys.backup) == bytes)

            let secondDamage = Data("[false]".utf8)
            defaults.set(secondDamage, forKey: key)
            let second = SessionReminderStore(contractOwnerID: ownerID, defaults: defaults)
            assert(second.canSaveReminders && second.reminders.isEmpty)
            second.saveReminders()
            assert(defaults.data(forKey: key) == Data("[]".utf8))
            assert(defaults.data(forKey: keys.backup) == bytes)
            SessionReminderStorage.clear(ownerID: ownerID, defaults: defaults)
            assert(defaults.object(forKey: key) == nil && defaults.object(forKey: keys.backup) == nil)
        }

        let failingSuite = "\(suite).backup-failure"
        let failingDefaults = SessionReminderContractDefaults(suiteName: failingSuite)!
        defer { failingDefaults.removePersistentDomain(forName: failingSuite) }
        failingDefaults.blockedKey = keys.backup
        let damaged = Data("{broken-json".utf8)
        failingDefaults.set(damaged, forKey: key)
        let protected = SessionReminderStore(contractOwnerID: ownerID, defaults: failingDefaults)
        assert(!protected.canSaveReminders && protected.preservedReminderData == damaged)
        let rejected = await protected.addReminder(courtName: "Blocked", weekday: .sunday,
            hour: 9, minute: 0, language: .english)
        assert(!rejected && protected.contractNotificationIDs?.isEmpty == true)
        protected.saveReminders()
        assert(failingDefaults.data(forKey: key) == damaged)
        assert(failingDefaults.object(forKey: keys.backup) == nil)
        let empty = load("[]")
        assert(empty.canSaveReminders && empty.preservedReminderData == nil)
        empty.saveReminders()
        assert(defaults.data(forKey: key) == Data("[]".utf8))
        defaults.removeObject(forKey: key)
        let fresh = SessionReminderStore(contractOwnerID: ownerID, defaults: defaults)
        assert(fresh.canSaveReminders)
        fresh.saveReminders()
        assert(defaults.data(forKey: key) == Data("[]".utf8))
        print("SESSION-REMINDER-001 persistence checks passed: V1, backup bytes, recovered CRUD, first backup retained, cleanup, backup failure")
    }
#endif

    private func sortReminders() {
        reminders.sort {
            if $0.weekday.rawValue != $1.weekday.rawValue {
                return $0.weekday.rawValue < $1.weekday.rawValue
            }
            if $0.hour != $1.hour { return $0.hour < $1.hour }
            return $0.minute < $1.minute
        }
    }


    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            notificationCenter.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func requestAuthorizationFromCenter() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func addNotificationRequest(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            notificationCenter.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

#if DEBUG
private final class SessionReminderContractDefaults: UserDefaults {
    var blockedKey: String?

    override func set(_ value: Any?, forKey defaultName: String) {
        if defaultName != blockedKey { super.set(value, forKey: defaultName) }
    }
}
#endif
