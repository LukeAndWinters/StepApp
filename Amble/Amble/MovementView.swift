//
//  MovementView.swift
//  Amble
//
//  Movement display with optional graph
//

import SwiftUI
import Charts

struct MovementView: View {
    @EnvironmentObject private var detector: MovementDetector
    @EnvironmentObject private var screenTimeManager: ScreenTimeManager
    @State private var showGraph = false
    @State private var accelerationHistory: [Double] = []
    @State private var graphAnimationID = UUID()
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Main content - centered
                Spacer()
                
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
                    
                    // Blocking status indicator
                    if screenTimeManager.isBlocking {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(.red)
                            Text("Apps Blocked")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                    } else if !screenTimeManager.selectedActivityTokens.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.open.fill")
                                .foregroundStyle(.green)
                            Text("Apps Unlocked")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    
                    // Simple metrics
                    HStack(spacing: 40) {
                        VStack {
                            Text("\(detector.stepsInLast10Seconds)")
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                            Text("Steps/min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                    }
                    
                    // Toggle button for graph
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showGraph.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: showGraph ? "chart.line.uptrend.xyaxis" : "chart.line.uptrend.xyaxis")
                            Text(showGraph ? "Hide Graph" : "Show Graph")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                
                Spacer()
                
                // Acceleration graph (toggleable) - at bottom, no box
                if showGraph {
                    Chart {
                        ForEach(Array(accelerationHistory.enumerated()), id: \.offset) { index, value in
                            LineMark(
                                x: .value("Time", index),
                                y: .value("Accel", value)
                            )
                            .foregroundStyle(detector.isMoving ? .green : .red)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                    .frame(height: 80)
                    .chartYScale(domain: 0.8...1.2)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .padding(.horizontal)
                    .padding(.bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.linear(duration: 0.1), value: accelerationHistory.count)
                }
            }
        }
        .onChange(of: detector.accelerationMagnitude) { _, newValue in
            // Always store data, not just when graph is visible
            // Use withAnimation to smoothly transition the graph
            withAnimation(.linear(duration: 0.1)) {
                accelerationHistory.append(newValue)
                if accelerationHistory.count > 30 {
                    accelerationHistory.removeFirst()
                }
            }
        }
    }
    
    private var stateDescription: String {
        switch detector.movementState {
        case .walking: return "Walking detected"
        case .running: return "Running detected"
        case .inVehicle: return "In vehicle"
        case .stationary: return "Not moving"
        case .unknown: return "Detecting..."
        }
    }
}

#Preview {
    MovementView()
        .environmentObject(MovementDetector.shared)
        .environmentObject(ScreenTimeManager.shared)
}

