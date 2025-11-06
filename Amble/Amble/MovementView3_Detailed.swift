//
//  MovementView3_Detailed.swift
//  Amble
//
//  Detailed/Metrics movement display
//

import SwiftUI
import CoreMotion

struct MovementView3_Detailed: View {
    @StateObject private var detector = MovementDetector()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Status banner
                HStack {
                    StatusIndicator(isMoving: detector.isMoving, state: detector.movementState)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Movement Status")
                            .font(.headline)
                        Text(detailedStatusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(detector.isMoving ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                )
                
                // Main metrics
                VStack(alignment: .leading, spacing: 16) {
                    Text("Metrics")
                        .font(.headline)
                    
                    MetricRow(
                        icon: "figure.walk",
                        label: "Steps (last minute)",
                        value: "\(detector.stepsInLastMinute)",
                        color: .blue
                    )
                    
                    MetricRow(
                        icon: "waveform.path",
                        label: "Acceleration",
                        value: String(format: "%.3f g", detector.accelerationMagnitude),
                        color: .orange
                    )
                    
                    MetricRow(
                        icon: "speedometer",
                        label: "Estimated Speed",
                        value: String(format: "%.1f m/s (%.1f km/h)", detector.currentSpeed, detector.currentSpeed * 3.6),
                        color: .purple
                    )
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color(.secondarySystemBackground))
                )
                
                // Movement state details
                VStack(alignment: .leading, spacing: 16) {
                    Text("Movement State")
                        .font(.headline)
                    
                    StateDetailRow(
                        title: "Current State",
                        value: stateName,
                        icon: stateIcon,
                        color: stateColor
                    )
                    
                    StateDetailRow(
                        title: "App Access",
                        value: detector.isMoving ? "Allowed" : "Blocked",
                        icon: detector.isMoving ? "checkmark.circle.fill" : "xmark.circle.fill",
                        color: detector.isMoving ? .green : .red
                    )
                    
                    if detector.movementState == .inVehicle {
                        StateDetailRow(
                            title: "Vehicle Detection",
                            value: "Vehicle detected - apps blocked for safety",
                            icon: "car.fill",
                            color: .orange
                        )
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color(.secondarySystemBackground))
                )
                
                // Technical info
                VStack(alignment: .leading, spacing: 12) {
                    Text("Detection Method")
                        .font(.headline)
                    
                    InfoRow(label: "Accelerometer", value: detector.motionManager.isAccelerometerAvailable ? "Active" : "Unavailable")
                    InfoRow(label: "Activity Manager", value: CMMotionActivityManager.isActivityAvailable() ? "Active" : "Unavailable")
                    InfoRow(label: "Pedometer", value: CMPedometer.isStepCountingAvailable() ? "Active" : "Unavailable")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .padding()
        }
        .onAppear { detector.start() }
        .onDisappear { detector.stop() }
    }
    
    private var detailedStatusText: String {
        if detector.movementState == .inVehicle {
            return "Vehicle detected. Apps are blocked for safety."
        } else if detector.isMoving {
            return "Movement detected. Apps are accessible."
        } else {
            return "No movement detected. Apps are blocked."
        }
    }
    
    private var stateName: String {
        switch detector.movementState {
        case .walking: return "Walking"
        case .running: return "Running"
        case .inVehicle: return "In Vehicle"
        case .stationary: return "Stationary"
        case .unknown: return "Unknown"
        }
    }
    
    private var stateIcon: String {
        switch detector.movementState {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .inVehicle: return "car.fill"
        case .stationary: return "pause.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private var stateColor: Color {
        switch detector.movementState {
        case .walking, .running: return .green
        case .inVehicle: return .orange
        case .stationary: return .red
        case .unknown: return .gray
        }
    }
}

struct StatusIndicator: View {
    let isMoving: Bool
    let state: MovementState
    
    var body: some View {
        ZStack {
            Circle()
                .fill(indicatorColor)
                .frame(width: 50, height: 50)
            
            Image(systemName: indicatorIcon)
                .foregroundStyle(.white)
                .font(.title3)
        }
    }
    
    private var indicatorColor: Color {
        if state == .inVehicle {
            return .orange
        }
        return isMoving ? .green : .red
    }
    
    private var indicatorIcon: String {
        switch state {
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .inVehicle: return "car.fill"
        case .stationary: return "pause.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct MetricRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 30)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
        }
    }
}

struct StateDetailRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .fontWeight(.semibold)
            }
            Spacer()
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(value == "Active" ? .green : .red)
        }
    }
}

#Preview {
    MovementView3_Detailed()
}

