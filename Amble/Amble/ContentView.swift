//
//  ContentView.swift
//  Amble
//
//  Created by Alessandro on 6/11/2025.
//

import SwiftUI
import Combine
import CoreMotion
import UserNotifications

final class PedometerViewModel: ObservableObject {
    @Published var stepsLastMinute: Int = 0
    @Published var activityDescription: String = "Unknown"
    @Published var isAuthorizedForMotion: Bool = true
    @Published var windowSeconds: Int = 60

    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()
    private var timer: Timer?
    private var lastZeroNotificationDate: Date?

    func start() {
        guard CMPedometer.isStepCountingAvailable() else {
            isAuthorizedForMotion = false
            return
        }

        // Ensure authorization prompt is shown on first launch if needed
        requestMotionAuthorizationIfNeeded()

        // Ask for local notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        // Start activity updates (optional but requested)
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: OperationQueue.main) { [weak self] activity in
                guard let activity = activity else { return }
                self?.activityDescription = Self.describe(activity)
            }
        }

        // Poll pedometer once per second for last 60s window
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activityManager.stopActivityUpdates()
    }

    private func requestMotionAuthorizationIfNeeded() {
        let now = Date()
        let oneSecondAgo = now.addingTimeInterval(-1)

        if CMPedometer.authorizationStatus() == .notDetermined {
            pedometer.queryPedometerData(from: oneSecondAgo, to: now) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.isAuthorizedForMotion = CMPedometer.authorizationStatus() == .authorized
                }
            }
        }

        if CMMotionActivityManager.authorizationStatus() == .notDetermined {
            activityManager.queryActivityStarting(from: oneSecondAgo, to: now, to: OperationQueue.main) { [weak self] _, _ in
                DispatchQueue.main.async {
                    // Keep a single boolean for simplicity; pedometer drives step access
                    self?.isAuthorizedForMotion = CMPedometer.authorizationStatus() == .authorized
                }
            }
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshStepsLastMinute()
        }
        // Fire immediately
        refreshStepsLastMinute()
    }

    private func refreshStepsLastMinute() {
        let now = Date()
        let start = now.addingTimeInterval(-TimeInterval(windowSeconds))
        pedometer.queryPedometerData(from: start, to: now) { [weak self] data, error in
            DispatchQueue.main.async {
                if error != nil {
                    // Reflect current pedometer authorization state on error
                    self?.isAuthorizedForMotion = CMPedometer.authorizationStatus() == .authorized
                    self?.stepsLastMinute = 0
                    return
                }
                self?.isAuthorizedForMotion = true
                let steps = data?.numberOfSteps.intValue ?? 0
                self?.stepsLastMinute = steps
                self?.maybeNotifyZeroSteps(currentSteps: steps)
            }
        }
    }

    private func maybeNotifyZeroSteps(currentSteps: Int) {
        guard currentSteps == 0 else { return }

        let now = Date()
        // Avoid spamming: notify at most once per window
        if let last = lastZeroNotificationDate, now.timeIntervalSince(last) < TimeInterval(windowSeconds) { return }
        lastZeroNotificationDate = now

        let content = UNMutableNotificationContent()
        content.title = "No steps detected"
        content.body = "You've been inactive for \(windowSeconds) seconds."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "steps-zero-\(now.timeIntervalSince1970)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private static func describe(_ a: CMMotionActivity) -> String {
        if a.walking { return "Walking" }
        if a.running { return "Running" }
        if a.cycling { return "Cycling" }
        if a.automotive { return "In Vehicle" }
        if a.stationary { return "Stationary" }
        return "Unknown"
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationView { MovementComparisonView() }
                .tabItem { Label("Movement", systemImage: "figure.walk.motion") }
            NavigationView { StepsView() }
                .tabItem { Label("Steps", systemImage: "chart.bar") }
            NavigationView { AppsView() }
                .tabItem { Label("Apps", systemImage: "app.badge") }
        }
    }
}

struct MovementComparisonView: View {
    @State private var selectedView = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // View selector
            Picker("View Style", selection: $selectedView) {
                Text("Minimal").tag(0)
                Text("Visual").tag(1)
                Text("Detailed").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Display selected view
            TabView(selection: $selectedView) {
                MovementView1_Minimal()
                    .tag(0)
                MovementView2_Visual()
                    .tag(1)
                MovementView3_Detailed()
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("Movement Detection")
    }
}

struct StepsView: View {
    @StateObject private var viewModel = PedometerViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Text("Steps in last minute")
                .font(.headline)

            Text("\(viewModel.stepsLastMinute)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 8) {
                Image(systemName: "figure.walk")
                Text(viewModel.activityDescription)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.isAuthorizedForMotion {
                Text("Motion access is not authorized. Enable Motion & Fitness in Settings → Privacy.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Inactivity window: \(viewModel.windowSeconds) seconds")
                    .font(.subheadline)
                Slider(value: Binding(
                    get: { Double(viewModel.windowSeconds) },
                    set: {
                        let clamped = min(max($0, 5), 600)
                        viewModel.windowSeconds = Int(clamped)
                    }
                ), in: 5...600, step: 5)
            }
        }
        .padding()
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .navigationTitle("Steps")
    }
}

#Preview {
    ContentView()
}
