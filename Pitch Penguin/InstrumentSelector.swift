//
//  InstrumentSelector.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import SwiftUI

struct InstrumentSelector: View {
    @Binding var selectedInstrument: InstrumentType
    @Binding var selectedTuningIndex: Int
    @State private var showTuningPicker = false

    var body: some View {
        VStack(spacing: 16) {
            // Instrument selection - minimal tabs with underline
            HStack(spacing: 32) {
                ForEach(InstrumentType.allCases, id: \.self) { instrument in
                    Button(action: {
                        selectedInstrument = instrument
                        selectedTuningIndex = 0
                    }) {
                        VStack(spacing: 4) {
                            Text(instrument.rawValue)
                                .font(.system(size: 15))
                                .foregroundColor(selectedInstrument == instrument ? .primary : .secondary)
                                .background(
                                    GeometryReader { geometry in
                                        Rectangle()
                                            .fill(selectedInstrument == instrument ? Color.primary : Color.clear)
                                            .frame(width: geometry.size.width, height: 2)
                                            .offset(y: geometry.size.height + 4)
                                    }
                                )
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // Tuning selection - dropdown style
            let tunings = TuningData.getTunings(for: selectedInstrument)
            Button(action: {
                showTuningPicker = true
            }) {
                HStack {
                    Text(tunings[selectedTuningIndex].name)
                        .font(.system(size: 14))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .offset(y: 10)
            .actionSheet(isPresented: $showTuningPicker) {
                ActionSheet(
                    title: Text("Select Tuning"),
                    buttons: tunings.enumerated().map { index, tuning in
                        .default(Text(tuning.name)) {
                            selectedTuningIndex = index
                        }
                    } + [.cancel()]
                )
            }
        }
    }
}
