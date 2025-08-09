//
//  StringSelector.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import SwiftUI

struct StringSelector: View {
    @Binding var selectedString: Int
    let strings: [GuitarString]
    let toneGenerator = ToneGenerator()
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<strings.count, id: \.self) { index in
                Button(action: {
                    selectedString = index
                    toneGenerator.playTone(frequency: strings[index].frequency, duration: 1.0)
                }) {
                    Text(strings[index].note)
                        .font(.title2)
                        .foregroundColor(selectedString == index ? Color(red: 0.95, green: 0.92, blue: 0.88) : .primary)
                        .frame(width: 40, height: 40)
                    .background(selectedString == index ? Color(red: 0.055, green: 0.059, blue: 0.063) : Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}