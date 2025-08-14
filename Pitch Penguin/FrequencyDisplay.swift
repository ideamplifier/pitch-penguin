//
//  FrequencyDisplay.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import SwiftUI

struct FrequencyDisplay: View {
    let currentFrequency: Double
    let targetFrequency: Double
    var isAutoMode: Bool = false
    var needlePosition: Double = 0
    
    private var cents: Double {
        guard currentFrequency > 0 && targetFrequency > 0 else { return 0 }
        return 1200 * log2(currentFrequency / targetFrequency)
    }
    
    private var statusText: String {
        if currentFrequency == 0 {
            return "Play a string"
        }
        
        // Use needle position instead of cents
        let absPosition = abs(needlePosition)
        if absPosition < 5 {
            return "Perfect!"
        } else if absPosition < 9 {
            return "Good"
        } else if absPosition < 20 {
            if needlePosition < 0 {
                return "Low"
            } else {
                return "High"
            }
        } else {
            if needlePosition < 0 {
                return "Too low"
            } else {
                return "Too high"
            }
        }
    }
    
    private var statusColor: Color {
        guard currentFrequency > 0 else { return Color(red: 0.055, green: 0.059, blue: 0.063) }  // 펭귄 검은색
        
        // Use needle position instead of cents
        let absPosition = abs(needlePosition)
        if absPosition < 9 {
            return .green  // Perfect or Good
        } else if needlePosition < 0 {
            return .yellow  // Low or Too low
        } else {
            return Color(red: 0.914, green: 0.384, blue: 0.173)  // #e9622c - High or Too high
        }
    }
    
    var body: some View {
        VStack(spacing: 15) {
            Text(statusText)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(statusColor)
                .frame(height: 34)
            
            HStack(spacing: 60) {
                VStack(alignment: .center, spacing: 4) {
                    Text("Current")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(height: 16)
                    Text(currentFrequency > 0 ? String(format: "%.1f Hz", currentFrequency) : "-- Hz")
                        .font(.title3)
                        .fontWeight(.medium)
                        .frame(width: 100, height: 28, alignment: .center)
                }
                .frame(width: 100)
                
                VStack(alignment: .center, spacing: 4) {
                    Text("Target")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(height: 16)
                    Text(targetFrequency > 0 ? String(format: "%.1f Hz", targetFrequency) : "-- Hz")
                        .font(.title3)
                        .fontWeight(.medium)
                        .frame(width: 100, height: 28, alignment: .center)
                }
                .frame(width: 100)
            }
            
        }
    }
}