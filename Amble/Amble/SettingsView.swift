import SwiftUI
import Combine
import FamilyControls
import CoreLocation

struct SettingsView: View {
    @EnvironmentObject private var screenTimeManager: ScreenTimeManager
    @EnvironmentObject private var detector: MovementDetector
    @State private var showScreenTimePicker = false

    var body: some View {
        List {
            // Blocking Status Section
            if !screenTimeManager.selectedActivityTokens.isEmpty {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: screenTimeManager.isBlocking ? "lock.shield.fill" : "lock.open.fill")
                                    .foregroundStyle(screenTimeManager.isBlocking ? .red : .green)
                                Text(screenTimeManager.isBlocking ? "Apps Blocked" : "Apps Unlocked")
                                    .font(.headline)
                            }
                            Text(blockingStatusDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Circle()
                            .fill(screenTimeManager.isBlocking ? Color.red : Color.green)
                            .frame(width: 12, height: 12)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Current Status")
                }
            }
            
            // Screen Time Section
            Section {
                if screenTimeManager.authorizationStatus == .approved {
                    Button(action: { showScreenTimePicker = true }) {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.tint)
                            Text("Select Apps to Block")
                            Spacer()
                            if !screenTimeManager.selectedActivityTokens.isEmpty {
                                Text("\(screenTimeManager.selectedActivityTokens.count) selected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .familyActivityPicker(
                        isPresented: $showScreenTimePicker,
                        selection: $screenTimeManager.selection
                    )
                    .onChange(of: screenTimeManager.selection) { _, newSelection in
                        screenTimeManager.saveSelection(newSelection)
                        // Re-apply blocking based on current movement state
                        screenTimeManager.updateBlocking(isAllowed: detector.isMoving)
                    }
                    
                    if !screenTimeManager.selectedActivityTokens.isEmpty {
                        Button(role: .destructive, action: {
                            screenTimeManager.clearSelectedTokens()
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear Selection")
                            }
                        }
                    }
                } else {
                    Button(action: {
                        Task {
                            await screenTimeManager.requestAuthorization()
                        }
                    }) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                            Text("Enable Screen Time Access")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text("App Selection")
            } footer: {
                if screenTimeManager.authorizationStatus == .approved {
                    Text("Selected apps will be blocked when you're not moving. Start moving to unlock them!")
                } else {
                    Text("Screen Time access is required to block apps. Your selections are stored locally on your device.")
                }
            }
            
            // Location Permission Section (for background monitoring)
            
            Section {
                HStack {
                    Image(systemName: locationIcon)
                        .foregroundStyle(locationIconColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Background Monitoring")
                            .font(.subheadline)
                        Text(locationStatusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if detector.locationAuthorizationStatus != .authorizedAlways {
                        Button("Enable") {
                            detector.requestLocationAuthorization()
                        }
                        .font(.subheadline)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                if detector.locationAuthorizationStatus != .authorizedAlways {
                    Text("Location access is needed to keep monitoring your movement when using other apps. Select \"Always Allow\" for best results.")
                }
            }

            // Battery & Performance Section
            Section {
                ForEach(LocationMonitoringLevel.allCases) { level in
                    Button(action: {
                        detector.monitoringLevel = level
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: level.icon)
                                .font(.title3)
                                .foregroundColor(level == detector.monitoringLevel ? .accentColor : .secondary)
                                .frame(width: 28)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(level.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if level == detector.monitoringLevel {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Battery & Performance")
            } footer: {
                Text("Controls how often the app checks your movement in the background. Higher levels respond faster but use more battery.")
            }
            
            // Notifications Section
            Section {
                Toggle(isOn: $detector.notifyOnStationary) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge")
                            .foregroundColor(.red)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("When Stationary")
                                .font(.subheadline)
                            Text("Alert when you stop moving")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Toggle(isOn: $detector.notifyOnMoving) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge")
                            .foregroundColor(.green)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("When Moving")
                                .font(.subheadline)
                            Text("Alert when you start moving")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if detector.notificationAuthorizationStatus == .denied {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Notifications disabled in Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Get notified when your movement state changes. Notifications are rate-limited to prevent spam.")
            }
            
            // How it works section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    howItWorksRow(icon: "figure.walk", title: "Moving", description: "Apps are unlocked when you're walking or running")
                    howItWorksRow(icon: "pause.circle", title: "Stationary", description: "Apps are blocked when you're not moving")
                    howItWorksRow(icon: "car.fill", title: "In Vehicle", description: "Apps are blocked when driving for safety")
                }
                .padding(.vertical, 4)
            } header: {
                Text("How It Works")
            }
        }
        .navigationTitle("Settings")
    }
    
    private var blockingStatusDescription: String {
        if screenTimeManager.isBlocking {
            return "Start moving to unlock your apps"
        } else {
            return "Keep moving to stay unlocked"
        }
    }
    
    private var locationIcon: String {
        switch detector.locationAuthorizationStatus {
        case .authorizedAlways:
            return "location.fill"
        case .authorizedWhenInUse:
            return "location"
        case .denied, .restricted:
            return "location.slash"
        default:
            return "location"
        }
    }
    
    private var locationIconColor: Color {
        switch detector.locationAuthorizationStatus {
        case .authorizedAlways:
            return .green
        case .authorizedWhenInUse:
            return .orange
        case .denied, .restricted:
            return .red
        default:
            return .secondary
        }
    }
    
    private var locationStatusDescription: String {
        switch detector.locationAuthorizationStatus {
        case .authorizedAlways:
            return "Always allowed - battery-efficient background monitoring"
        case .authorizedWhenInUse:
            return "Only while using - background monitoring limited"
        case .denied:
            return "Denied - enable in Settings > Privacy > Location"
        case .restricted:
            return "Restricted by device policy"
        case .notDetermined:
            return "Not yet requested"
        @unknown default:
            return "Unknown status"
        }
    }
    
    @ViewBuilder
    private func howItWorksRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationView { SettingsView() }
        .environmentObject(ScreenTimeManager.shared)
        .environmentObject(MovementDetector.shared)
}


