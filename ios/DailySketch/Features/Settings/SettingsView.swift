import SwiftUI

struct SettingsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel: SettingsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                LoadingView(message: "Loading settings…")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .task {
            if viewModel == nil {
                let model = SettingsViewModel(
                    auth: dependencies.auth,
                    preferencesService: dependencies.preferencesService,
                    reminderSync: dependencies.reminderSync,
                    appearanceStore: dependencies.appearanceStore,
                    analytics: dependencies.analytics
                )
                viewModel = model
                await model.load()
            }
        }
        .onAppear {
            Task { await viewModel?.refreshReminderPermissionStatus() }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: SettingsViewModel) -> some View {
        @Bindable var model = viewModel
        List {
            accountSection
            if dependencies.auth.isAuthenticated {
                notificationsSection(model)
                sketchPreferencesSection(model)
                appearanceSection(model)
                safetySection
                deleteAccountSection
            }
            aboutSection
            if let error = model.errorMessage {
                Section {
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger)
                        .accessibilityLabel(error)
                }
            }
        }
        .disabled(model.isSaving)
        .overlay {
            if model.isLoading {
                LoadingView(message: "Loading preferences…")
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section("Account") {
            if dependencies.auth.isAuthenticated {
                if let user = dependencies.auth.currentUser {
                    LabeledContent("Display name", value: user.displayName)
                    LabeledContent("Username", value: user.username.map { "@\($0)" } ?? "Not set")
                    if !user.profileCompleted {
                        Button("Complete Profile") {
                            dependencies.navigation.profilePath.append(.profileCompletion)
                        }
                        .accessibilityLabel("Complete Profile")
                    }
                }
                Button("Sign Out", role: .destructive) {
                    Task {
                        await dependencies.auth.signOut()
                        dependencies.navigation.profilePath.removeAll()
                    }
                }
                .accessibilityLabel("Sign Out")
            } else {
                Text("Browsing as guest")
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func notificationsSection(_ model: SettingsViewModel) -> some View {
        Section("Notifications") {
            Toggle("Daily Reminder", isOn: Binding(
                get: { model.preferences.notificationsEnabled },
                set: { enabled in
                    Task { await model.setNotificationsEnabled(enabled) }
                }
            ))
            .tint(AppColors.primary)
            .accessibilityLabel("Daily Reminder")

            if model.preferences.notificationsEnabled {
                DatePicker(
                    "Reminder Time",
                    selection: Binding(
                        get: { model.reminderTimeDate },
                        set: { date in
                            Task { await model.setReminderTime(date) }
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .accessibilityLabel("Reminder Time")

                Text("The reminder announces when today’s daily prompt is ready.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            if model.showsOpenSettingsForNotifications {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .accessibilityLabel("Open Settings to allow notifications")
                Text("Notifications are disabled in iOS Settings.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.danger)
            } else if model.reminderPermissionStatus == .denied {
                Text("Notifications are disabled in iOS Settings.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func sketchPreferencesSection(_ model: SettingsViewModel) -> some View {
        Section("Sketch Preferences") {
            Toggle("Remember Timer Choice", isOn: Binding(
                get: { model.preferences.rememberTimerOption },
                set: { enabled in
                    Task { await model.setRememberTimer(enabled) }
                }
            ))
            .tint(AppColors.primary)
            .accessibilityLabel("Remember Timer Choice")

            if model.preferences.rememberTimerOption {
                Picker("Default Timer", selection: Binding(
                    get: { model.selectedTimer ?? .fiveMinutes },
                    set: { option in
                        Task { await model.setTimerOption(option) }
                    }
                )) {
                    ForEach(TimerPreferenceOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .accessibilityLabel("Default Timer")
            }
        }
    }

    @ViewBuilder
    private func appearanceSection(_ model: SettingsViewModel) -> some View {
        Section("Appearance") {
            Picker("Appearance", selection: Binding(
                get: { model.preferences.appearance },
                set: { value in
                    Task { await model.setAppearance(value) }
                }
            )) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.inline)
            .accessibilityLabel("Appearance")
        }
    }

    private var safetySection: some View {
        Section("Safety and privacy") {
            Button("Blocked Users") {
                dependencies.navigation.profilePath.append(.blockedUsers)
            }
            .accessibilityLabel("Blocked Users")
            Text("Community Guidelines")
                .foregroundStyle(AppColors.textSecondary)
            Text("Privacy Policy")
                .foregroundStyle(AppColors.textSecondary)
            Text("Terms of Service")
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var deleteAccountSection: some View {
        Section {
            Button("Delete Account", role: .destructive) {
                dependencies.navigation.profilePath.append(.deleteAccount)
            }
            .accessibilityLabel("Delete Account")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "0.1.0")
            Text("Timezone for reminders: \(TimeZone.current.identifier)")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}

#Preview("Authenticated") {
    NavigationStack {
        SettingsView()
    }
    .environment(AppDependencies.live)
}

#Preview("Dark") {
    NavigationStack {
        SettingsView()
    }
    .environment(AppDependencies.live)
    .preferredColorScheme(.dark)
}
