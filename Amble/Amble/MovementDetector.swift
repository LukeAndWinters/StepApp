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

enum MovementState {
    case stationary
    case walking
    case running
    case inVehicle
    case unknown
}

@MainActor
final class MovementDetector: NSObject, ObservableObject {
    static let shared = MovementDetector()
    
    @Published var isMoving: Bool = false {
        didSet {
            if oldValue != isMoving {
                onMovementStateChanged?(isMoving)
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
    
    // Thresholds
    private let accelerationThreshold: Double = 0.1 // g-force threshold for movement
    private let vehicleSpeedThreshold: Double = 5.0 // m/s (~18 km/h) - likely in vehicle
    private let updateInterval: TimeInterval = 0.1 // 10 Hz
    private let stepsGracePeriod: TimeInterval = 10.0 // Seconds to consider recent steps
    private let backgroundCheckInterval: TimeInterval = 30.0 // Check every 30 seconds in background
    
    private var accelerationHistory: [Double] = []
    private let historySize = 10 // Keep last 10 readings
    private var lastStepCount: Int = 0
    
    override init() {
        super.init()
        setupLocationManager()
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
        print("Entering background mode...")
        
        // Stop continuous location updates (battery drain)
        locationManager.stopUpdatingLocation()
        
        // Start significant location changes (very battery efficient)
        // This wakes the app when user moves ~500m between cell towers
        if locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startMonitoringSignificantLocationChanges()
            print("Started significant location monitoring")
        }
        
        // Start a background wake timer that briefly enables location to keep CoreMotion alive
        startBackgroundWakeTimer()
    }
    
    /// Call when app enters foreground
    func enterForeground() {
        isInBackground = false
        print("Entering foreground mode...")
        
        // Stop significant location monitoring
        locationManager.stopMonitoringSignificantLocationChanges()
        backgroundWakeTimer?.invalidate()
        backgroundWakeTimer = nil
        
        // Query recent activity to update state immediately
        queryRecentActivity()
    }
    
    /// Periodic timer to briefly wake location services and allow CoreMotion to update
    private func startBackgroundWakeTimer() {
        backgroundWakeTimer?.invalidate()
        backgroundWakeTimer = Timer.scheduledTimer(withTimeInterval: backgroundCheckInterval, repeats: true) { [weak self] _ in
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

