//
//  MovementView2_Visual.swift
//  Amble
//
//  Visual/Graphical movement display
//

import SwiftUI
import Charts

struct MovementView2_Visual: View {
    @StateObject private var detector = MovementDetector()
    @State private var accelerationHistory: [Double] = []
    
    var body: some View {
        VStack(spacing: 20) {
            // Large status card
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detector.isMoving ? "ACTIVE" : "INACTIVE")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    Text(stateEmoji)
                        .font(.system(size: 60))
                    
                    Text(stateText)
                        .font(.system(size: 18, weight: .semibold))
                }
                
                Spacer()
                
                // Circular progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .trim(from: 0, to: movementProgress)
                        .stroke(
                            detector.isMoving ? Color.green : Color.red,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: movementProgress)
                    
                    Text("\(Int(movementProgress * 100))%")
                        .font(.system(size: 20, weight: .bold))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: detector.isMoving ? .green.opacity(0.2) : .red.opacity(0.2), radius: 10)
            )
            
            // Acceleration graph
            VStack(alignment: .leading, spacing: 8) {
                Text("Acceleration")
                    .font(.headline)
                
                Chart {
                    ForEach(Array(accelerationHistory.enumerated()), id: \.offset) { index, value in
                        LineMark(
                            x: .value("Time", index),
                            y: .value("Accel", value)
                        )
                        .foregroundStyle(detector.isMoving ? .green : .red)
                    }
                }
                .frame(height: 120)
                .chartYScale(domain: 0.8...1.2)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color(.secondarySystemBackground))
            )
            
            // Metrics grid
            HStack(spacing: 15) {
                MetricCard(title: "Steps/min", value: "\(detector.stepsInLastMinute)", icon: "figure.walk")
                MetricCard(title: "Speed", value: String(format: "%.1f m/s", detector.currentSpeed), icon: "speedometer")
                MetricCard(title: "State", value: stateShort, icon: "waveform.path")
            }
        }
        .padding()
        .onAppear {
            detector.start()
            startAccelerationTracking()
        }
        .onDisappear {
            detector.stop()
        }
        .onChange(of: detector.accelerationMagnitude) { _, newValue in
            accelerationHistory.append(newValue)
            if accelerationHistory.count > 30 {
                accelerationHistory.removeFirst()
            }
        }
    }
    
    private var movementProgress: Double {
        switch detector.movementState {
        case .running: return 1.0
        case .walking: return 0.7
        case .inVehicle: return 0.0
        case .stationary: return 0.0
        case .unknown: return 0.3
        }
    }
    
    private var stateEmoji: String {
        switch detector.movementState {
        case .walking: return "🚶"
        case .running: return "🏃"
        case .inVehicle: return "🚗"
        case .stationary: return "🛑"
        case .unknown: return "❓"
        }
    }
    
    private var stateText: String {
        switch detector.movementState {
        case .walking: return "Walking"
        case .running: return "Running"
        case .inVehicle: return "In Vehicle"
        case .stationary: return "Stationary"
        case .unknown: return "Detecting"
        }
    }
    
    private var stateShort: String {
        switch detector.movementState {
        case .walking: return "Walk"
        case .running: return "Run"
        case .inVehicle: return "Vehicle"
        case .stationary: return "Still"
        case .unknown: return "?"
        }
    }
    
    private func startAccelerationTracking() {
        accelerationHistory = []
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    MovementView2_Visual()
}

