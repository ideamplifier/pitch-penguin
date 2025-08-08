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
    
    private var cents: Double {
        guard currentFrequency > 0 && targetFrequency > 0 else { return 0 }
        return 1200 * log2(currentFrequency / targetFrequency)
    }
    
    private var needleRotation: Double {
        return max(-45, min(45, cents / 50 * 45))
    }
    
    private var meterColor: Color {
        let absCents = abs(cents)
        if absCents < 5 {
            return .green
        } else if absCents < 15 {
            return .yellow
        } else {
            return .red
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Arc(startAngle: .degrees(225), endAngle: .degrees(315))
                    .stroke(Color.gray.opacity(0.3), lineWidth: 20)
                
                Arc(startAngle: .degrees(225), endAngle: .degrees(315))
                    .trim(from: 0, to: CGFloat((needleRotation + 45) / 90))
                    .stroke(meterColor, lineWidth: 20)
                
                ForEach([-45, -30, -15, 0, 15, 30, 45], id: \.self) { angle in
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 2, height: 10)
                        .offset(y: -geometry.size.height * 0.35)
                        .rotationEffect(.degrees(Double(angle) + 270))
                }
                
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 3, height: geometry.size.height * 0.4)
                    .offset(y: -geometry.size.height * 0.2)
                    .rotationEffect(.degrees(needleRotation + 270))
                
                Circle()
                    .fill(Color.black)
                    .frame(width: 15, height: 15)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct Arc: Shape {
    var startAngle: Angle
    var endAngle: Angle
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width * 0.35,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false)
        return path
    }
}