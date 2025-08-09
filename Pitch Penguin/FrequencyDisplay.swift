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
    
    private var cents: Double {
        guard currentFrequency > 0 && targetFrequency > 0 else { return 0 }
        return 1200 * log2(currentFrequency / targetFrequency)
    }
    
    private var statusText: String {
        if currentFrequency == 0 {
            return "Play a string"
        }
        
        let absCents = abs(cents)
        if absCents < 5 {
            return "Perfect!"
        } else if cents < 0 {
            return "Too low"
        } else {
            return "Too high"
        }
    }
    
    private var statusColor: Color {
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
                    Text(String(format: "%.1f Hz", targetFrequency))
                        .font(.title3)
                        .fontWeight(.medium)
                        .frame(width: 100, height: 28, alignment: .center)
                }
                .frame(width: 100)
            }
            
        }
    }
}