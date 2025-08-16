//
//  TuningMeter.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import SwiftUI

struct TuningMeter: View {
    let targetFrequency: Double
    let currentFrequency: Double
    @Binding var needlePosition: Double
    var directCents: Double? = nil  // Direct cents from AudioKit
    
    @State private var animatedRotation: Double = 0
    @State private var previousRotation: Double = 0
    
    // Use the unified needle mapper for consistent behavior
    private let needleMapper = TuningNeedleMapper()
    
    private var cents: Double {
        // Use direct cents if provided (from AudioKit which knows the actual detected note)
        // This is critical for auto mode where the needle should show deviation from the detected note
        if let directCents = directCents {
            return directCents
        }
        // Fallback to frequency comparison
        guard currentFrequency > 0 && targetFrequency > 0 else { return 0 }
        return 1200 * log2(currentFrequency / targetFrequency)
    }
    
    private var meterColor: Color {
        guard currentFrequency > 0 else { return .gray }
        
        // Use animated rotation position instead of raw cents
        let absRotation = abs(animatedRotation)
        if absRotation < 9 {
            return .green  // Perfect or Good
        } else if animatedRotation < 0 {
            return .yellow  // Low or Too low
        } else {
            return Color(red: 0.914, green: 0.384, blue: 0.173)  // #e9622c - High or Too high
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Arc(startAngle: .degrees(225), endAngle: .degrees(315))
                    .stroke(Color.gray.opacity(0.3), lineWidth: 15)
                
                Arc(startAngle: .degrees(225), endAngle: .degrees(315))
                    .trim(from: 0, to: CGFloat((animatedRotation + 45) / 90))
                    .stroke(meterColor, lineWidth: 15)
                    .animation(.easeInOut(duration: 0.1), value: animatedRotation)
                
                ForEach([-45, -30, -15, 0, 15, 30, 45], id: \.self) { angle in
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 2, height: 10)
                        .offset(y: -geometry.size.height * 0.4)
                        .rotationEffect(.degrees(Double(angle) + 360))
                }
                
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 3, height: geometry.size.height * 0.45)
                    .offset(y: -geometry.size.height * 0.225)
                    .rotationEffect(.degrees(animatedRotation + 360))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0), value: animatedRotation)
                
                Circle()
                    .fill(Color.black)
                    .frame(width: 15, height: 15)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            animatedRotation = 0
        }
        .onChange(of: currentFrequency) { oldValue, newValue in
            // If we have direct cents from AudioKit, use that directly
            // This is especially important for auto mode
            let newRotation: Double
            if let directCents = directCents {
                // Convert cents directly to rotation (-50 to +50 cents maps to -45 to +45 degrees)
                newRotation = max(-45, min(45, directCents * 0.9))
            } else {
                // Fall back to needle mapper for manual mode
                newRotation = needleMapper.rotationDegrees(
                    currentHz: currentFrequency,
                    targetHz: targetFrequency,
                    previousDegrees: animatedRotation,
                    maxAngle: 45.0
                )
            }
            
            withAnimation(.linear(duration: 0.05)) {
                animatedRotation = newRotation
                needlePosition = newRotation  // Update binding
            }
        }
    }
}

struct Arc: Shape {
    var startAngle: Angle
    var endAngle: Angle
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY + 50),
                    radius: rect.width * 0.4,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false)
        return path
    }
}