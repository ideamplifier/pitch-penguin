//
//  StringSelector.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import SwiftUI

struct StringSelector: View {
    @EnvironmentObject var audioEngine: AudioKitPitchTuner
    @Binding var selectedString: Int
    let strings: [GuitarString]
    let accuracyStates: [Bool]
    let currentFrequency: Double
    var isDisabled: Bool = false
    
    private func getBackgroundColor(for index: Int) -> Color {
        if selectedString == index && !isDisabled {
            // 선택된 현 - 검정색 (Auto 모드가 아닐 때만)
            return Color(red: 0.055, green: 0.059, blue: 0.063)
        } else {
            // 선택되지 않은 현 - 항상 회색
            return Color.gray.opacity(0.1)
        }
    }
    
    private func getTextColor(for index: Int) -> Color {
        if selectedString == index && !isDisabled {
            // 선택된 현 - 베이지색 (Auto 모드가 아닐 때만)
            return Color(red: 0.95, green: 0.92, blue: 0.88)
        } else {
            // 선택되지 않은 현
            return .primary
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<strings.count, id: \.self) { index in
                Button(action: {
                    if !isDisabled {
                        selectedString = index
                    }
                    audioEngine.playTone(frequency: strings[index].frequency)
                }) {
                    Text(strings[index].note)
                        .font(.title2)
                        .foregroundColor(getTextColor(for: index))
                        .frame(width: 40, height: 40)
                        .background(getBackgroundColor(for: index))
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}