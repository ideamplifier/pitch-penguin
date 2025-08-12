//
//  SimpleContentView.swift
//  Pitch Penguin
//
//  Simplified tuner that works reliably
//

import SwiftUI

struct SimpleContentView: View {
    @StateObject private var tuner = SimpleTuner()
    @State private var rotationDegrees: Double = 0
    
    private let needleMapper = TuningNeedleMapper()
    
    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.92, blue: 0.88)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("Pitch Penguin")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 40)
                
                // Note display
                Text(tuner.note)
                    .font(.system(size: 72, weight: .bold))
                    .frame(height: 100)
                
                // Frequency display
                Text(String(format: "%.1f Hz", tuner.frequency))
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                // Needle meter
                ZStack {
                    // Background arc
                    SimpleArc(startAngle: .degrees(225), endAngle: .degrees(315))
                        .stroke(Color.gray.opacity(0.3), lineWidth: 15)
                        .frame(width: 200, height: 200)
                    
                    // Tick marks
                    ForEach([-45, -30, -15, 0, 15, 30, 45], id: \.self) { angle in
                        Rectangle()
                            .fill(Color.gray)
                            .frame(width: 2, height: 10)
                            .offset(y: -80)
                            .rotationEffect(.degrees(Double(angle)))
                    }
                    
                    // Needle
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: 3, height: 90)
                        .offset(y: -45)
                        .rotationEffect(.degrees(rotationDegrees))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: rotationDegrees)
                    
                    // Center dot
                    Circle()
                        .fill(Color.black)
                        .frame(width: 15, height: 15)
                }
                .frame(width: 200, height: 200)
                
                // Cents display
                Text(String(format: "%+.0f cents", tuner.cents))
                    .font(.title3)
                    .foregroundColor(abs(tuner.cents) < 5 ? .green : .orange)
                
                Spacer()
                
                // Control buttons
                HStack(spacing: 40) {
                    Button("Start") {
                        tuner.start()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Stop") {
                        tuner.stop()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .padding()
        }
        .onAppear {
            tuner.start()
        }
        .onDisappear {
            tuner.stop()
        }
        .onChange(of: tuner.frequency) { _, _ in
            updateNeedle()
        }
    }
    
    private func updateNeedle() {
        // Find target frequency for current note
        let targetHz = findTargetFrequency()
        
        // Use the needle mapper for smooth movement
        rotationDegrees = needleMapper.rotationDegrees(
            currentHz: tuner.frequency,
            targetHz: targetHz,
            previousDegrees: rotationDegrees,
            maxAngle: 45.0
        )
    }
    
    private func findTargetFrequency() -> Double {
        guard tuner.frequency > 0 else { return 440.0 }
        
        // Find nearest semitone
        let noteNum = 12 * log2(tuner.frequency / 440.0) + 69
        let nearestNote = Int(round(noteNum))
        return 440.0 * pow(2.0, Double(nearestNote - 69) / 12.0)
    }
}

struct SimpleArc: Shape {
    var startAngle: Angle
    var endAngle: Angle
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width * 0.4,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false)
        return path
    }
}

#Preview {
    SimpleContentView()
}