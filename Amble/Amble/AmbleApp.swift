//
//  AmbleApp.swift
//  Amble
//
//  Created by Alessandro on 6/11/2025.
//

import SwiftUI
import BackgroundTasks

@main
struct AmbleApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    private static let backgroundTaskIdentifier = "com.amble.movement-check"
    
    init() {
        registerBackgroundTasks()
        // Set up callback SYNCHRONOUSLY before starting detector
        setupMovementCallback()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ScreenTimeManager.shared)
                .environmentObject(MovementDetector.shared)
                .onAppear {
                    // Start detector when view appears
                    startDetectorAndApplyInitialState()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Enter background mode - use battery-efficient monitoring
                Task { @MainActor in
                    MovementDetector.shared.enterBackground()
                }
                scheduleBackgroundTask()
            case .active:
                // Enter foreground mode - full monitoring
                Task { @MainActor in
                    MovementDetector.shared.enterForeground()
                    startDetectorAndApplyInitialState()
                }
            case .inactive:
                // App is transitioning, do nothing special
                break
            @unknown default:
                break
            }
        }
    }
    
    /// Set up the callback synchronously - this must happen before detector starts
    private func setupMovementCallback() {
        MovementDetector.shared.onMovementStateChanged = { isMoving in
            // isMoving == true means allowed state (user is moving)
            // isMoving == false means not allowed (block apps)
            Task { @MainActor in
                ScreenTimeManager.shared.updateBlocking(isAllowed: isMoving)
                print("Movement changed: isMoving=\(isMoving), blocking=\(!isMoving)")
            }
        }
    }
    
    private func startDetectorAndApplyInitialState() {
        Task { @MainActor in
            // Start the detector (if not already running)
            if !MovementDetector.shared.isRunning {
                MovementDetector.shared.start()
            }
            
            // Wait briefly for initial activity query to complete
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Apply initial blocking state based on current movement
            ScreenTimeManager.shared.updateBlocking(isAllowed: MovementDetector.shared.isMoving)
            print("Initial state applied: isMoving=\(MovementDetector.shared.isMoving)")
        }
    }
    
    // MARK: - Background Tasks
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundTask(task as! BGProcessingTask)
        }
    }
    
    private func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        // Schedule to run as soon as possible
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60) // 1 minute from now
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background task scheduled")
        } catch {
            print("Could not schedule background task: \(error)")
        }
    }
    
    private func handleBackgroundTask(_ task: BGProcessingTask) {
        // Schedule the next background task
        scheduleBackgroundTask()
        
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Check movement state and update blocking
        Task { @MainActor in
            // Query recent activity
            MovementDetector.shared.start()
            
            // Give it a moment to get activity data
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Update blocking based on current state
            ScreenTimeManager.shared.updateBlocking(isAllowed: MovementDetector.shared.isMoving)
            print("Background task: isMoving=\(MovementDetector.shared.isMoving)")
            
            task.setTaskCompleted(success: true)
        }
    }
}
