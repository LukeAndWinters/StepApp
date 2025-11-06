//
//  MovementView1_Minimal.swift
//  Amble
//
//  Minimal/Clean movement display
//

import SwiftUI

struct MovementView1_Minimal: View {
    @StateObject private var detector = MovementDetector()
    
    var body: some View {
        VStack(spacing: 40) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(detector.isMoving ? Color.green : Color.red)
                    .frame(width: 120, height: 120)
                    .shadow(color: detector.isMoving ? .green.opacity(0.3) : .red.opacity(0.3), radius: 20)
                
                Image(systemName: detector.isMoving ? "figure.walk" : "pause.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 8) {
                Text(detector.isMoving ? "Moving" : "Stationary")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                
                Text(stateDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Simple metrics
            HStack(spacing: 40) {
                VStack {
                    Text("\(detector.stepsInLastMinute)")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("Steps/min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack {
                    Text(String(format: "%.1f", detector.accelerationMagnitude))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text("Accel (g)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .onAppear { detector.start() }
        .onDisappear { detector.stop() }
    }
    
    private var stateDescription: String {
        switch detector.movementState {
        case .walking: return "Walking detected"
        case .running: return "Running detected"
        case .inVehicle: return "In vehicle - apps blocked"
        case .stationary: return "Not moving"
        case .unknown: return "Detecting..."
        }
    }
}

#Preview {
    MovementView1_Minimal()
}

