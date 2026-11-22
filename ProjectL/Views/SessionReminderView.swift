import SwiftUI
import UIKit
import UserNotifications

struct SessionReminderView: View {
    @ObservedObject var store: SessionReminderStore
    let initialCourtName: String?

    @Environment(\.openURL) private var openURL
    @State private var isShowingEditor = false
    @State private var editingReminder: SessionReminder?
    @State private var reminderPendingDeletion: SessionReminder?

    init(store: SessionReminderStore, initialCourtName: String? = nil) {
        self.store = store
        self.initialCourtName = initialCourtName
    }

    private var copy: AppCopy { AppCopy() }
    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { isPresented in
                if !isPresented { store.clearError() }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    eyebrow: String(localized: "Court schedule"),
                    title: String(localized: "Session reminders"),
                    subtitle: String(localized: "Set a weekly reminder for your regular court time.")
                )

                permissionSection
                remindersSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background { CommunityBackdrop() }
        .navigationTitle(String(localized: "Session reminders"))
        .navigationBarTitleDisplayMode(.inline)
        .localizedBackButton()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentNewReminder()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Add session reminder"))
                .accessibilityIdentifier("add-session-reminder-button")
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            SessionReminderEditorView(
                store: store,
                initialCourtName: initialCourtName,
                reminder: editingReminder
            )
        }
        .task {
            await store.refreshAuthorizationStatus()
            await store.restoreScheduledReminders(language: .english)
        }
        .confirmationDialog(
            String(localized: "Delete this reminder?"),
            isPresented: Binding(
                get: { reminderPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { reminderPendingDeletion = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete reminder"), role: .destructive) {
                if let reminderPendingDeletion {
                    store.removeReminder(reminderPendingDeletion)
                }
                reminderPendingDeletion = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                reminderPendingDeletion = nil
            }
        } message: {
            Text(String(localized: "You can create the reminder again later. Other accounts are not affected."))
        }
        .alert(
            String(localized: "Reminder could not be updated"),
            isPresented: errorPresented
        ) {
            if store.lastError == .permissionDenied {
                Button(String(localized: "Open Settings")) {
                    openNotificationSettings()
                }
            }
            Button(copy.dismissTitle, role: .cancel) {
                store.clearError()
            }
        } message: {
            Text(errorMessage)
        }
    }

    private var permissionSection: some View {
        WarmCard {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(permissionTitle)
                } icon: {
                    Image(systemName: permissionIcon).foregroundStyle(Color.inkBrown)
                }
                .font(.headline)
                .foregroundStyle(Color.inkBrown)

                Text(permissionMessage)
                    .font(.subheadline)
                    .foregroundStyle(Color.mutedBrown)
                    .lineSpacing(3)

                switch store.authorizationStatus {
                case .notDetermined:
                    Button {
                        Task { await store.requestAuthorization() }
                    } label: {
                        Label(
                            String(localized: "Allow reminders"),
                            systemImage: "bell.badge"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SessionReminderActionButtonStyle())
                    .disabled(store.isUpdating)
                    .accessibilityIdentifier("request-session-reminder-permission-button")
                case .denied:
                    Button {
                        openNotificationSettings()
                    } label: {
                        Label(
                            String(localized: "Open Settings"),
                            systemImage: "gear"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SessionReminderActionButtonStyle())
                    .accessibilityIdentifier("open-session-reminder-settings-button")
                default:
                    EmptyView()
                }
            }
        }
        .accessibilityIdentifier("session-reminder-permission-card")
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Your reminders"))
                    .font(.title3.bold())
                    .foregroundStyle(Color.inkBrown)
                Spacer()
                Button {
                    presentNewReminder()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.olive)
                }
                .accessibilityLabel(String(localized: "Add session reminder"))
                .accessibilityIdentifier("session-reminder-section-add-button")
            }

            if store.reminders.isEmpty {
                WarmCard {
                    VStack(spacing: 10) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.warmGold)
                        Text(String(localized: "No session reminders yet. Add one for your regular court time."))
                        .font(.subheadline)
                        .foregroundStyle(Color.mutedBrown)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                }
                .accessibilityIdentifier("session-reminder-empty-state")
            } else {
                WarmCard {
                    VStack(spacing: 0) {
                        ForEach(Array(store.reminders.enumerated()), id: \.element.id) { index, reminder in
                            reminderRow(reminder)

                            if index < store.reminders.count - 1 {
                                Divider().overlay(Color.olive.opacity(0.12))
                            }
                        }
                    }
                }
                .accessibilityIdentifier("session-reminder-list")
            }

            Text(String(localized: "Reminders stay on this device and use system notifications at the selected weekly time."))
            .font(.caption)
            .foregroundStyle(Color.mutedBrown)
            .lineSpacing(3)
        }
    }

    private func reminderRow(_ reminder: SessionReminder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.isEnabled ? "bell.fill" : "bell.slash")
                .font(.body.weight(.semibold))
                .foregroundStyle(reminder.isEnabled ? Color.warmGold : Color.mutedBrown)
                .frame(width: 34, height: 34)
                .background(Color.warmGold.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.courtName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.inkBrown)
                Text("\(reminder.weekday.title(for: .english)) · \(reminder.timeText(for: .english))")
                    .font(.caption)
                    .foregroundStyle(Color.mutedBrown)
            }

            Spacer()

            Button {
                Task {
                    await store.setEnabled(!reminder.isEnabled, for: reminder.id, language: .english)
                }
            } label: {
                Image(systemName: reminder.isEnabled ? "pause.circle" : "play.circle")
                    .font(.title3)
                    .foregroundStyle(Color.olive)
            }
            .disabled(store.isUpdating)
            .accessibilityLabel(reminder.isEnabled
                ? String(localized: "Disable reminder")
                : String(localized: "Enable reminder"))
            .accessibilityIdentifier("toggle-session-reminder-\(reminder.id.uuidString)")

            Button {
                editingReminder = reminder
                isShowingEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(Color.olive)
            .disabled(store.isUpdating)
            .accessibilityLabel(String(localized: "Edit reminder"))
            .accessibilityIdentifier("edit-session-reminder-\(reminder.id.uuidString)")

            Button(role: .destructive) {
                reminderPendingDeletion = reminder
            } label: {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
            }
            .accessibilityLabel(String(localized: "Delete reminder"))
            .accessibilityIdentifier("delete-session-reminder-\(reminder.id.uuidString)")
        }
        .padding(.vertical, 12)
    }

    private func presentNewReminder() {
        editingReminder = nil
        isShowingEditor = true
    }

    private var permissionTitle: String {
        switch store.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            String(localized: "Reminders are enabled")
        case .denied:
            String(localized: "Reminders are disabled")
        case .notDetermined:
            String(localized: "Enable system reminders")
        @unknown default:
            String(localized: "Reminder status unavailable")
        }
    }

    private var permissionIcon: String {
        switch store.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "bell.fill"
        case .denied: "bell.slash.fill"
        case .notDetermined: "bell.badge"
        @unknown default: "bell"
        }
    }

    private var permissionMessage: String {
        switch store.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            String(localized: "Weekly reminders will arrive at the time you choose.")
        case .denied:
            String(localized: "Allow notifications in Settings to receive session reminders.")
        case .notDetermined:
            String(localized: "Allow notifications to receive a reminder at the time you choose.")
        @unknown default:
            String(localized: "The system reminder status is unavailable right now.")
        }
    }

    private var errorMessage: String {
        switch store.lastError {
        case .permissionDenied:
            String(localized: "Notifications are not allowed. Enable them in Settings and try again.")
        case .schedulingFailed:
            String(localized: "This reminder could not be saved. Please try again later.")
        case .none:
            ""
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct SessionReminderEditorView: View {
    @ObservedObject var store: SessionReminderStore
    let initialCourtName: String?
    let reminder: SessionReminder?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var courtName: String
    @State private var weekday: SessionWeekday = .sunday
    @State private var time: Date
    @State private var isShowingInvalidName = false

    init(
        store: SessionReminderStore,
        initialCourtName: String?,
        reminder: SessionReminder? = nil
    ) {
        self.store = store
        self.initialCourtName = initialCourtName
        self.reminder = reminder
        _courtName = State(initialValue: reminder?.courtName ?? initialCourtName ?? "")
        _weekday = State(initialValue: reminder?.weekday ?? .sunday)
        _time = State(
            initialValue: Self.date(hour: reminder?.hour ?? 10, minute: reminder?.minute ?? 0)
        )
    }

    private var copy: AppCopy { AppCopy() }
    private var isEditing: Bool { reminder != nil }
    private var editorTitle: String {
        isEditing
            ? String(localized: "Edit session reminder")
            : String(localized: "New session reminder")
    }
    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.lastError != nil },
            set: { isPresented in
                if !isPresented { store.clearError() }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WarmCard {
                        VStack(alignment: .leading, spacing: 16) {
                            TextField(
                                String(localized: "Court name"),
                                text: $courtName
                            )
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("session-reminder-court-name-field")

                            Picker(
                                String(localized: "Day of the week"),
                                selection: $weekday
                            ) {
                                ForEach(SessionWeekday.allCases) { day in
                                    Text(day.title(for: .english)).tag(day)
                                }
                            }
                            .accessibilityIdentifier("session-reminder-weekday-picker")

                            DatePicker(
                                String(localized: "Reminder time"),
                                selection: $time,
                                displayedComponents: .hourAndMinute
                            )
                            .accessibilityLabel(String(localized: "Reminder time"))
                            .accessibilityIdentifier("session-reminder-time-picker")
                        }
                    }

                    Text(isEditing
                        ? String(localized: "This updates the weekly reminder on this device. You can disable or delete it later.")
                        : String(localized: "This creates a repeating weekly reminder on this device. You can disable or delete it later."))
                    .font(.caption)
                    .foregroundStyle(Color.mutedBrown)
                    .lineSpacing(3)
                }
                .padding(20)
            }
            .background { CommunityBackdrop() }
            .navigationTitle(editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        save()
                    }
                    .disabled(store.isUpdating)
                    .accessibilityIdentifier("save-session-reminder-button")
                }
            }
            .alert(
                String(localized: "Enter a court name"),
                isPresented: $isShowingInvalidName
            ) {
                Button(copy.dismissTitle, role: .cancel) {}
            } message: {
                Text(String(localized: "Enter a court or session name for this reminder."))
            }
            .alert(
                String(localized: "Reminder could not be updated"),
                isPresented: errorPresented
            ) {
                if store.lastError == .permissionDenied {
                    Button(String(localized: "Open Settings")) {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                }
                Button(copy.dismissTitle, role: .cancel) {
                    store.clearError()
                }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func save() {
        let trimmedName = courtName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            isShowingInvalidName = true
            return
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        Task {
            let saved: Bool
            if let reminder {
                saved = await store.updateReminder(
                    id: reminder.id,
                    courtName: trimmedName,
                    weekday: weekday,
                    hour: components.hour ?? 10,
                    minute: components.minute ?? 0,
                    language: .english
                )
            } else {
                saved = await store.addReminder(
                    courtName: trimmedName,
                    weekday: weekday,
                    hour: components.hour ?? 10,
                    minute: components.minute ?? 0,
                    language: .english
                )
            }
            if saved { dismiss() }
        }
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }

    private var errorMessage: String {
        switch store.lastError {
        case .permissionDenied:
            String(localized: "Notifications are not allowed. Enable them in Settings and try again.")
        case .schedulingFailed:
            String(localized: "This reminder could not be saved. Please try again later.")
        case .none:
            ""
        }
    }
}

private struct SessionReminderActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.softCream)
            .padding(.vertical, 11)
            .background(Color.olive.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
