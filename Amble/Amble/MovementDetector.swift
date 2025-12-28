//
//  MovementDetector.swift
//  Amble
//
//  Created on 6/11/2025.
//

import Foundation
import CoreMotion
import CoreLocation
import Combine
import UserNotifications

enum MovementState {
    case stationary
    case walking
    case running
    case inVehicle
    case unknown
}

/// Location monitoring level - trades off battery usage vs responsiveness
enum LocationMonitoringLevel: Int, CaseIterable, Identifiable {
    case significantChangesOnly = 0  // Most battery efficient
    case lowPower = 1                // Periodic checks every 60s
    case balanced = 2                // Periodic checks every 30s
    case responsive = 3              // Periodic checks every 15s
    case continuous = 4              // Always on (most battery drain)
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .significantChangesOnly: return "Minimal"
        case .lowPower: return "Low Power"
        case .balanced: return "Balanced"
        case .responsive: return "Responsive"
        case .continuous: return "Continuous"
        }
    }
    
    var description: String {
        switch self {
        case .significantChangesOnly: return "Only checks when you move ~500m"
        case .lowPower: return "Checks every 60 seconds"
        case .balanced: return "Checks every 30 seconds"
        case .responsive: return "Checks every 15 seconds"
        case .continuous: return "Always monitoring (uses more battery)"
        }
    }
    
    var icon: String {
        switch self {
        case .significantChangesOnly: return "leaf"
        case .lowPower: return "battery.75percent"
        case .balanced: return "battery.50percent"
        case .responsive: return "battery.25percent"
        case .continuous: return "bolt.fill"
        }
    }
    
    var checkInterval: TimeInterval {
        switch self {
        case .significantChangesOnly: return 0 // No periodic checks
        case .lowPower: return 60
        case .balanced: return 30
        case .responsive: return 15
        case .continuous: return 0 // Always on
        }
    }
    
    var usesContinuousLocation: Bool {
        self == .continuous
    }
    
    var usesSignificantChanges: Bool {
        self == .significantChangesOnly
    }
}

@MainActor
final class MovementDetector: NSObject, ObservableObject {
    static let shared = MovementDetector()
    
    private static let monitoringLevelKey = "locationMonitoringLevel"
    private static let notifyOnStationaryKey = "notifyOnStationary"
    private static let notifyOnMovingKey = "notifyOnMoving"
    
    @Published var isMoving: Bool = false {
        didSet {
            if oldValue != isMoving {
                onMovementStateChanged?(isMoving)
                sendMovementNotificationIfNeeded(isMoving: isMoving)
            }
        }
    }
    @Published var movementState: MovementState = .unknown
    @Published var accelerationMagnitude: Double = 0.0
    @Published var currentSpeed: Double = 0.0 // m/s
    @Published var stepsInLast10Seconds: Int = 0
    @Published var isRunning: Bool = false
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isInBackground: Bool = false
    @Published var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    
    /// Current location monitoring level
    @Published var monitoringLevel: LocationMonitoringLevel {
        didSet {
            UserDefaults.standard.set(monitoringLevel.rawValue, forKey: Self.monitoringLevelKey)
            if isInBackground {
                applyMonitoringLevel()
            }
        }
    }
    
    /// Whether to notify when becoming stationary
    @Published var notifyOnStationary: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnStationary, forKey: Self.notifyOnStationaryKey)
            if notifyOnStationary {
                requestNotificationPermission()
            }
        }
    }
    
    /// Whether to notify when starting to move
    @Published var notifyOnMoving: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnMoving, forKey: Self.notifyOnMovingKey)
            if notifyOnMoving {
                requestNotificationPermission()
            }
        }
    }
    
    /// Whether recent steps were detected (within the grace period)
    @Published var hasRecentSteps: Bool = false
    
    /// Callback triggered when movement state changes
    var onMovementStateChanged: ((Bool) -> Void)?
    
    let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()
    private let locationManager = CLLocationManager()
    private var stepsTimer: Timer?
    private var recentStepsTimer: Timer?
    private var backgroundWakeTimer: Timer?
    private var lastNotificationDate: Date?
    private let notificationCooldown: TimeInterval = 10.0 // Minimum seconds between notifications
    
    // Thresholds
    private let accelerationThreshold: Double = 0.1 // g-force threshold for movement
    private let vehicleSpeedThreshold: Double = 5.0 // m/s (~18 km/h) - likely in vehicle
    private let updateInterval: TimeInterval = 0.1 // 10 Hz
    private let stepsGracePeriod: TimeInterval = 10.0 // Seconds to consider recent steps
    
    private var accelerationHistory: [Double] = []
    private let historySize = 10 // Keep last 10 readings
    private var lastStepCount: Int = 0
    
    override init() {
        // Load saved settings
        let savedLevel = UserDefaults.standard.integer(forKey: Self.monitoringLevelKey)
        self.monitoringLevel = LocationMonitoringLevel(rawValue: savedLevel) ?? .balanced
        self.notifyOnStationary = UserDefaults.standard.bool(forKey: Self.notifyOnStationaryKey)
        self.notifyOnMoving = UserDefaults.standard.bool(forKey: Self.notifyOnMovingKey)
        
        super.init()
        setupLocationManager()
        checkNotificationAuthorizationStatus()
    }
    
    // MARK: - Notifications
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.checkNotificationAuthorizationStatus()
                if let error = error {
                    print("Notification permission error: \(error)")
                }
            }
        }
    }
    
    private func checkNotificationAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.notificationAuthorizationStatus = settings.authorizationStatus
            }
        }
    }
    
    private func sendMovementNotificationIfNeeded(isMoving: Bool) {
        // Check if notifications are enabled for this state
        guard (isMoving && notifyOnMoving) || (!isMoving && notifyOnStationary) else {
            return
        }
        
        // Cooldown to prevent notification spam
        if let lastDate = lastNotificationDate,
           Date().timeIntervalSince(lastDate) < notificationCooldown {
            return
        }
        
        lastNotificationDate = Date()
        
        let content = UNMutableNotificationContent()
        
        if isMoving {
            content.title = "You're Moving! 🚶"
            content.body = "Apps are now unlocked. Keep moving!"
        } else {
            content.title = "You've Stopped 🛑"
            content.body = "Apps are now blocked. Start moving to unlock them."
        }
        
        // No sound by default (silent notification)
        // Use a fixed identifier so new notifications replace the previous one
        let request = UNNotificationRequest(
            identifier: "amble-movement-status",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced // Imprecise location - battery efficient
        locationManager.distanceFilter = CLLocationDistanceMax // Only significant changes
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = false // No blue bar - we use significant changes
        locationAuthorizationStatus = locationManager.authorizationStatus
    }
    
    func start() {
        // Stop any existing updates first to prevent duplicates
        if isRunning {
            stop()
        }
        
        isRunning = true
        print("MovementDetector starting...")
        
        // Request location authorization and start updates for background execution
        requestLocationAuthorization()
        
        // Query recent activity immediately to get current state
        queryRecentActivity()
        
        guard motionManager.isAccelerometerAvailable else {
            print("Accelerometer not available")
            return
        }
        
        // Start accelerometer updates
        motionManager.accelerometerUpdateInterval = updateInterval
        motionManager.startAccelerometerUpdates(to: OperationQueue.main) { [weak self] data, error in
            guard let self = self, let acceleration = data?.acceleration else { return }
            if let error = error {
                print("Accelerometer error: \(error)")
                return
            }
            
            // Calculate magnitude of acceleration
            let magnitude = sqrt(
                pow(acceleration.x, 2) +
                pow(acceleration.y, 2) +
                pow(acceleration.z, 2)
            )
            
            self.accelerationMagnitude = magnitude
            self.accelerationHistory.append(magnitude)
            if self.accelerationHistory.count > self.historySize {
                self.accelerationHistory.removeFirst()
            }
            
            // Determine if moving based on acceleration variance
            self.updateMovementState()
        }
        
        // Start activity updates for better classification
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: OperationQueue.main) { [weak self] activity in
                guard let self = self, let activity = activity else { return }
                self.updateStateFromActivity(activity)
            }
        }
        
        // Start pedometer for step counting - use live updates for immediate detection
        if CMPedometer.isStepCountingAvailable() {
            startLivePedometerUpdates()
            scheduleStepsPolling()
        }
    }
    
    func stop() {
        isRunning = false
        motionManager.stopAccelerometerUpdates()
        activityManager.stopActivityUpdates()
        pedometer.stopUpdates()
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        stepsTimer?.invalidate()
        stepsTimer = nil
        recentStepsTimer?.invalidate()
        recentStepsTimer = nil
        backgroundWakeTimer?.invalidate()
        backgroundWakeTimer = nil
        print("MovementDetector stopped")
    }
    
    // MARK: - Background/Foreground handling
    
    /// Call when app enters background
    func enterBackground() {
        isInBackground = true
        print("Entering background mode with level: \(monitoringLevel.title)")
        
        applyMonitoringLevel()
    }
    
    /// Call when app enters foreground
    func enterForeground() {
        isInBackground = false
        print("Entering foreground mode...")
        
        // Stop all background monitoring
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopUpdatingLocation()
        backgroundWakeTimer?.invalidate()
        backgroundWakeTimer = nil
        
        // Query recent activity to update state immediately
        queryRecentActivity()
    }
    
    /// Apply the current monitoring level settings
    private func applyMonitoringLevel() {
        guard isInBackground else { return }
        guard locationManager.authorizationStatus == .authorizedAlways ||
              locationManager.authorizationStatus == .authorizedWhenInUse else {
            print("Location not authorized, cannot apply monitoring level")
            return
        }
        
        // Stop any existing monitoring
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        backgroundWakeTimer?.invalidate()
        backgroundWakeTimer = nil
        
        print("Applying monitoring level: \(monitoringLevel.title)")
        
        switch monitoringLevel {
        case .significantChangesOnly:
            // Only use significant location changes - most battery efficient
            if locationManager.authorizationStatus == .authorizedAlways {
                locationManager.startMonitoringSignificantLocationChanges()
                print("Using significant location changes only")
            }
            
        case .continuous:
            // Keep location always on - most responsive but drains battery
            locationManager.startUpdatingLocation()
            print("Using continuous location updates")
            
        case .lowPower, .balanced, .responsive:
            // Use periodic timer + significant changes
            if locationManager.authorizationStatus == .authorizedAlways {
                locationManager.startMonitoringSignificantLocationChanges()
            }
            startBackgroundWakeTimer()
            print("Using periodic checks every \(monitoringLevel.checkInterval)s + significant changes")
        }
    }
    
    /// Periodic timer to briefly wake location services and allow CoreMotion to update
    private func startBackgroundWakeTimer() {
        backgroundWakeTimer?.invalidate()
        
        let interval = monitoringLevel.checkInterval
        guard interval > 0 else { return }
        
        backgroundWakeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.performBackgroundCheck()
        }
    }
    
    /// Perform a background check - briefly enable location, query CoreMotion, then disable
    private func performBackgroundCheck() {
        guard isInBackground else { return }
        
        print("Background wake - checking movement state...")
        
        // Briefly start location updates to keep app execution
        if locationManager.authorizationStatus == .authorizedAlways ||
           locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.startUpdatingLocation()
        }
        
        // Query CoreMotion for current state
        queryRecentActivity()
        
        // Also check recent steps
        let now = Date()
        let tenSecondsAgo = now.addingTimeInterval(-10)
        pedometer.queryPedometerData(from: tenSecondsAgo, to: now) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if error == nil, let steps = data?.numberOfSteps.intValue, steps > 0 {
                    self.hasRecentSteps = true
                    self.updateMovementState()
                }
                
                // Stop location updates after brief check (save battery)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if self.isInBackground {
                        self.locationManager.stopUpdatingLocation()
                        print("Background check complete - location stopped")
                    }
                }
            }
        }
    }
    
    // MARK: - Location Authorization
    
    func requestLocationAuthorization() {
        locationAuthorizationStatus = locationManager.authorizationStatus
        
        switch locationManager.authorizationStatus {
        case .notDetermined:
            // First request "When In Use" - this shows the imprecise location option
            // The delegate will then request "Always" after user grants "When In Use"
            print("Requesting location authorization (When In Use first)...")
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // User granted When In Use - now request Always for background
            print("Have When In Use, requesting Always...")
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            print("Location authorized (Always)")
            if isInBackground {
                locationManager.startMonitoringSignificantLocationChanges()
            }
        case .denied, .restricted:
            print("Location access denied or restricted")
        @unknown default:
            break
        }
    }
    
    /// Query recent activity to get immediate state (useful on startup or wake)
    private func queryRecentActivity() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        
        let now = Date()
        let fiveSecondsAgo = now.addingTimeInterval(-5)
        
        activityManager.queryActivityStarting(from: fiveSecondsAgo, to: now, to: OperationQueue.main) { [weak self] activities, error in
            guard let self = self, error == nil, let activities = activities, let lastActivity = activities.last else { return }
            self.updateStateFromActivity(lastActivity)
        }
    }
    
    // MARK: - Pedometer
    
    /// Live pedometer updates for immediate step detection
    private func startLivePedometerUpdates() {
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let self = self, error == nil, let data = data else { return }
            
            DispatchQueue.main.async {
                let currentSteps = data.numberOfSteps.intValue
                
                // Detect new steps
                if currentSteps > self.lastStepCount {
                    self.onStepsDetected()
                }
                self.lastStepCount = currentSteps
            }
        }
    }
    
    /// Called when new steps are detected - triggers grace period
    private func onStepsDetected() {
        hasRecentSteps = true
        updateMovementState()
        
        // Reset the grace period timer
        recentStepsTimer?.invalidate()
        recentStepsTimer = Timer.scheduledTimer(withTimeInterval: stepsGracePeriod, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.hasRecentSteps = false
                self?.updateMovementState()
            }
        }
    }
    
    /// Periodic polling for steps in time windows (for display purposes)
    private func scheduleStepsPolling() {
        stepsTimer?.invalidate()
        stepsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStepCounts()
        }
        updateStepCounts()
    }
    
    private func updateStepCounts() {
        let now = Date()
        
        // Steps in last 10 seconds
        let start10 = now.addingTimeInterval(-10)
        pedometer.queryPedometerData(from: start10, to: now) { [weak self] data, error in
            DispatchQueue.main.async {
                if error == nil {
                    self?.stepsInLast10Seconds = data?.numberOfSteps.intValue ?? 0
                }
            }
        }
    }
    
    private func updateMovementState() {
        // In vehicle always blocks - safety first
        if movementState == .inVehicle {
            isMoving = false
            return
        }
        
        // If activity says walking/running - immediately allow
        if movementState == .walking || movementState == .running {
            isMoving = true
            return
        }
        
        // If recent steps detected (within grace period) - allow
        // This catches steady walking that activity detection might miss
        if hasRecentSteps {
            isMoving = true
            return
        }
        
        // Activity says stationary and no recent steps - block
        if movementState == .stationary {
            isMoving = false
            return
        }
        
        // Unknown state - use accelerometer as fallback
        guard accelerationHistory.count >= 5 else { return }
        
        let mean = accelerationHistory.reduce(0, +) / Double(accelerationHistory.count)
        let variance = accelerationHistory.map { pow($0 - mean, 2) }.reduce(0, +) / Double(accelerationHistory.count)
        
        // Higher threshold to avoid false positives from small movements
        let isAccelerating = variance > 0.02
        isMoving = isAccelerating
    }
    
    private func updateStateFromActivity(_ activity: CMMotionActivity) {
        if activity.automotive {
            movementState = .inVehicle
            currentSpeed = vehicleSpeedThreshold + 5.0
        } else if activity.running {
            movementState = .running
            currentSpeed = 3.0 // ~10.8 km/h average running speed
        } else if activity.walking {
            movementState = .walking
            currentSpeed = 1.4 // ~5 km/h average walking speed
        } else if activity.stationary {
            movementState = .stationary
            currentSpeed = 0.0
        } else {
            movementState = .unknown
        }
        
        updateMovementState()
    }
}

// MARK: - CLLocationManagerDelegate
extension MovementDetector: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            locationAuthorizationStatus = manager.authorizationStatus
            print("Location authorization changed: \(manager.authorizationStatus.rawValue)")
            
            switch manager.authorizationStatus {
            case .authorizedAlways:
                // Start significant location monitoring for background
                print("Location authorized (Always) - enabling background monitoring")
                if isInBackground {
                    manager.startMonitoringSignificantLocationChanges()
                }
            case .authorizedWhenInUse:
                // User just granted "When In Use" - immediately request "Always" for background
                print("Got When In Use - now requesting Always authorization...")
                // Small delay to let the first dialog dismiss before showing the second
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                manager.requestAlwaysAuthorization()
            default:
                break
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Location updates wake the app - use this opportunity to check CoreMotion
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            // Update speed from GPS if available
            if location.speed >= 0 {
                currentSpeed = location.speed
            }
            
            // Query CoreMotion for current activity state
            queryRecentActivity()
            
            print("Location update - checking movement. Speed: \(location.speed) m/s, Background: \(isInBackground)")
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Ignore location unknown errors (common when no GPS fix)
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        print("Location error: \(error.localizedDescription)")
    }
}

