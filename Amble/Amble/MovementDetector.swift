//
//  MovementDetector.swift
//  Amble
//
//  Created on 6/11/2025.
//

import Foundation
import CoreMotion
import Combine

enum MovementState {
    case stationary
    case walking
    case running
    case inVehicle
    case unknown
}

@MainActor
final class MovementDetector: ObservableObject {
    @Published var isMoving: Bool = false
    @Published var movementState: MovementState = .unknown
    @Published var accelerationMagnitude: Double = 0.0
    @Published var currentSpeed: Double = 0.0 // m/s
    @Published var stepsInLastMinute: Int = 0
    
    let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()
    private var timer: Timer?
    
    // Thresholds
    private let accelerationThreshold: Double = 0.1 // g-force threshold for movement
    private let vehicleSpeedThreshold: Double = 5.0 // m/s (~18 km/h) - likely in vehicle
    private let updateInterval: TimeInterval = 0.1 // 10 Hz
    
    private var accelerationHistory: [Double] = []
    private let historySize = 10 // Keep last 10 readings
    
    func start() {
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
        
        // Start pedometer for step counting
        if CMPedometer.isStepCountingAvailable() {
            schedulePedometerUpdate()
        }
    }
    
    func stop() {
        motionManager.stopAccelerometerUpdates()
        activityManager.stopActivityUpdates()
        timer?.invalidate()
        timer = nil
    }
    
    private func schedulePedometerUpdate() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateSteps()
        }
        updateSteps()
    }
    
    private func updateSteps() {
        let now = Date()
        let start = now.addingTimeInterval(-60)
        pedometer.queryPedometerData(from: start, to: now) { [weak self] data, error in
            DispatchQueue.main.async {
                if error == nil {
                    self?.stepsInLastMinute = data?.numberOfSteps.intValue ?? 0
                }
            }
        }
    }
    
    private func updateMovementState() {
        guard accelerationHistory.count >= 5 else { return }
        
        // Calculate variance in acceleration (movement causes variation)
        let mean = accelerationHistory.reduce(0, +) / Double(accelerationHistory.count)
        let variance = accelerationHistory.map { pow($0 - mean, 2) }.reduce(0, +) / Double(accelerationHistory.count)
        
        // If variance is high, user is likely moving
        let isAccelerating = variance > 0.01 || accelerationMagnitude > (1.0 + accelerationThreshold)
        
        // Update isMoving based on accelerometer and activity state
        if movementState == .inVehicle {
            isMoving = false // Block apps when in vehicle
        } else {
            isMoving = isAccelerating || stepsInLastMinute > 0 || movementState == .walking || movementState == .running
        }
    }
    
    private func updateStateFromActivity(_ activity: CMMotionActivity) {
        if activity.automotive {
            movementState = .inVehicle
            // Estimate speed from activity confidence (rough approximation)
            // In reality, you'd need GPS for accurate speed, but we can infer from activity
            currentSpeed = activity.automotive ? vehicleSpeedThreshold + 5.0 : 0.0
            isMoving = false // Don't allow app use in vehicle
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

