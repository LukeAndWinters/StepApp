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
            NavigationView { MovementView() }
                .tabItem { Label("Movement", systemImage: "figure.walk.motion") }
            NavigationView { AppsView() }
                .tabItem { Label("Apps", systemImage: "app.badge") }
        }
    }
}

#Preview {
    ContentView()
}
