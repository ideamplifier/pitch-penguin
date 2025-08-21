//
//  StringSelector.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import SwiftUI

struct StringSelector: View {
    @EnvironmentObject var audioEngine: AudioKitPitchTuner
    let strings: [GuitarString]

    private func getBackgroundColor(for index: Int) -> Color {
        return Color.gray.opacity(0.1)
    }

    private func getTextColor(for index: Int) -> Color {
        return .primary
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0 ..< strings.count, id: \.self) { index in
                Button(action: {
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