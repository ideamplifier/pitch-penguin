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
    
    var body: some View {
        HStack(spacing: 15) {
            ForEach(0..<strings.count, id: \.self) { index in
                Button(action: {
                    selectedString = index
                }) {
                    VStack {
                        Text(strings[index].note)
                            .font(.title2)
                            .fontWeight(selectedString == index ? .bold : .regular)
                        Text("\(strings[index].octave)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 50, height: 50)
                    .background(selectedString == index ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selectedString == index ? Color.blue : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}