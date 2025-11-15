//
//  ContentView.swift
//  tachy-app
//
//  Created by Laksh Bharani on 11/8/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some View {
        ZStack {
            // White background
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Connection status
                Text(bluetoothManager.connectionStatus)
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding(.top)
                
                // Graph title
                Text("PPG Voltage (Last 5 Seconds)")
                    .font(.title2)
                    .foregroundColor(.black)
                    .padding(.top, 10)
                
                // Voltage graph (last 5 seconds)
                VoltageGraphView(voltageHistory: bluetoothManager.recentVoltageHistory)
                    .frame(height: 300)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                
                // Current voltage display (smaller)
                Text(String(format: "Current: %.3f V", bluetoothManager.ppgVoltage))
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
                    .padding(.bottom, 5)
                
                // Peak counter and BPM
                VStack(spacing: 8) {
                    Text("Peaks (>2.8V): \(bluetoothManager.peakCount)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.blue)
                    
                    Text(String(format: "BPM: %.1f", bluetoothManager.bpm))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                }
                .padding(.bottom, 10)
                
                // Connect/Disconnect button
                Button(action: {
                    if bluetoothManager.isConnected {
                        bluetoothManager.disconnect()
                    } else {
                        bluetoothManager.startScanning()
                    }
                }) {
                    Text(bluetoothManager.isConnected ? "Disconnect" : "Connect")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(bluetoothManager.isConnected ? Color.red : Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
                .disabled(bluetoothManager.isScanning)
            }
        }
    }
}

struct VoltageGraphView: View {
    let voltageHistory: [(time: Date, voltage: Float)]
    private let peakThreshold: Float = 2.8
    
    private var minVoltage: Float {
        guard !voltageHistory.isEmpty else { return 0.0 }
        let min = voltageHistory.map { $0.voltage }.min() ?? 0.0
        return min - abs(min * 0.05) // Add 5% padding below
    }
    
    private var maxVoltage: Float {
        guard !voltageHistory.isEmpty else { return 5.0 }
        let max = voltageHistory.map { $0.voltage }.max() ?? 5.0
        return max + (max * 0.05) // Add 5% padding above
    }
    
    private let leftPadding: CGFloat = 45
    private let rightPadding: CGFloat = 15
    private let topPadding: CGFloat = 15
    private let bottomPadding: CGFloat = 30
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Y-axis labels (positioned absolutely)
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(0..<6) { i in
                        let value = maxVoltage - (Float(i) / Float(5)) * (maxVoltage - minVoltage)
                        Text(String(format: "%.2f", value))
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .frame(height: (geometry.size.height - topPadding - bottomPadding) / 5, alignment: .trailing)
                    }
                }
                .frame(width: leftPadding - 5, height: geometry.size.height - topPadding - bottomPadding)
                .offset(x: 0, y: topPadding)
                
                // Graph area
                ZStack(alignment: .topLeading) {
                    // Grid lines
                    GraphGridLinesView(
                        width: geometry.size.width - leftPadding - rightPadding,
                        height: geometry.size.height - topPadding - bottomPadding,
                        numHorizontalLines: 5,
                        numVerticalLines: 4
                    )
                    .offset(x: leftPadding, y: topPadding)
                    
                    // Threshold line at 2.8V
                    if !voltageHistory.isEmpty {
                        let graphWidth = geometry.size.width - leftPadding - rightPadding
                        let graphHeight = geometry.size.height - topPadding - bottomPadding
                        let voltageRange = maxVoltage - minVoltage
                        
                        if voltageRange > 0 && peakThreshold >= minVoltage && peakThreshold <= maxVoltage {
                            Path { path in
                                let normalizedThreshold = (peakThreshold - minVoltage) / voltageRange
                                let y = topPadding + graphHeight - (CGFloat(normalizedThreshold) * graphHeight)
                                
                                path.move(to: CGPoint(x: leftPadding, y: y))
                                path.addLine(to: CGPoint(x: geometry.size.width - rightPadding, y: y))
                            }
                            .stroke(Color.red.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                        }
                    }
                    
                    // Voltage line graph
                    if !voltageHistory.isEmpty {
                        Path { path in
                            let graphWidth = geometry.size.width - leftPadding - rightPadding
                            let graphHeight = geometry.size.height - topPadding - bottomPadding
                            
                            let voltageRange = maxVoltage - minVoltage
                            guard voltageRange > 0 else { return }
                            
                            for (index, dataPoint) in voltageHistory.enumerated() {
                                let x = leftPadding + (CGFloat(index) / CGFloat(max(voltageHistory.count - 1, 1))) * graphWidth
                                let normalizedVoltage = (dataPoint.voltage - minVoltage) / voltageRange
                                let y = topPadding + graphHeight - (CGFloat(normalizedVoltage) * graphHeight)
                                
                                if index == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(Color.blue, lineWidth: 2.5)
                    } else {
                        // Empty state
                        Text("Waiting for data...")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: .gray.opacity(0.2), radius: 5, x: 0, y: 2)
    }
}

struct GraphGridLinesView: View {
    let width: CGFloat
    let height: CGFloat
    let numHorizontalLines: Int
    let numVerticalLines: Int
    
    var body: some View {
        Path { path in
            // Horizontal grid lines
            for i in 0...numHorizontalLines {
                let y = (CGFloat(i) / CGFloat(numHorizontalLines)) * height
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
            
            // Vertical grid lines
            for i in 0...numVerticalLines {
                let x = (CGFloat(i) / CGFloat(numVerticalLines)) * width
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
            }
        }
        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
    }
}

#Preview {
    ContentView()
}
