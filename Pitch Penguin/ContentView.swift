//
//  ContentView.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedString = 0
    @State private var isListening = true
    @State private var penguinState: PenguinState = .waiting
    @State private var showPermissionAlert = false
    @State private var delayTimer: Timer?
    @State private var selectedInstrument: InstrumentType = .guitar
    @State private var selectedTuningIndex = 0
    
    @StateObject private var audioEngine = AudioEngine()
    
    private var currentTuning: Tuning {
        let tunings = TuningData.getTunings(for: selectedInstrument)
        return tunings[selectedTuningIndex]
    }
    
    private var currentStrings: [GuitarString] {
        return currentTuning.notes
    }
    
    private var detectedNote: String {
        guard audioEngine.detectedFrequency > 0 else { return "--" }
        
        // Find closest note
        let allNotes = [
            (note: "C", frequency: 65.41),
            (note: "C#", frequency: 69.30),
            (note: "D", frequency: 73.42),
            (note: "D#", frequency: 77.78),
            (note: "E", frequency: 82.41),
            (note: "F", frequency: 87.31),
            (note: "F#", frequency: 92.50),
            (note: "G", frequency: 98.00),
            (note: "G#", frequency: 103.83),
            (note: "A", frequency: 110.00),
            (note: "A#", frequency: 116.54),
            (note: "B", frequency: 123.47)
        ]
        
        let freq = audioEngine.detectedFrequency
        var octave = 4
        var baseFreq = freq
        
        // Find octave
        while baseFreq > 123.47 * 2 {
            baseFreq /= 2
            octave += 1
        }
        while baseFreq < 65.41 {
            baseFreq *= 2
            octave -= 1
        }
        
        // Find closest note
        let closest = allNotes.min(by: { abs($0.frequency - baseFreq) < abs($1.frequency - baseFreq) })
        return "\(closest?.note ?? "--")\(octave)"
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.92, blue: 0.88)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("Pitch Penguin")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 40)
                
                VStack(spacing: -80) {
                    ZStack {
                        TuningMeter(targetFrequency: currentStrings[safe: selectedString]?.frequency ?? 0,
                                  currentFrequency: audioEngine.detectedFrequency)
                            .frame(height: 180)
                        
                        // Display detected note
                        VStack(spacing: 4) {
                            Text(detectedNote)
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.primary)
                            
                            if audioEngine.detectedFrequency > 0, let targetFreq = currentStrings[safe: selectedString]?.frequency {
                                let cents = 1200 * log2(audioEngine.detectedFrequency / targetFreq)
                                Text(String(format: "%+.0f cents", cents))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .offset(y: -150)
                    }
                    
                    PenguinView(state: penguinState)
                        .frame(width: 120, height: 120)
                        .offset(y: 3)
                }
                .padding(.vertical, 20)
                .offset(y: 80)
                
                FrequencyDisplay(currentFrequency: audioEngine.detectedFrequency,
                               targetFrequency: currentStrings[safe: selectedString]?.frequency ?? 0)
                    .padding(.top, 30)
                    .offset(y: 10)
                
                Spacer()
                
                StringSelector(selectedString: $selectedString, strings: currentStrings)
                    .padding(.horizontal)
                
                InstrumentSelector(selectedInstrument: $selectedInstrument, 
                                 selectedTuningIndex: $selectedTuningIndex)
                    .padding(.horizontal)
                    .padding(.bottom, 30)
            }
        }
        .onAppear {
            startListening()
        }
        .onChange(of: audioEngine.detectedFrequency) { _, newValue in
            if let targetFreq = currentStrings[safe: selectedString]?.frequency {
                updatePenguinState(currentFrequency: newValue, targetFrequency: targetFreq)
            }
        }
        .onChange(of: selectedInstrument) { _, _ in
            selectedString = 0 // Reset to first string when changing instrument
        }
        .onChange(of: selectedTuningIndex) { _, _ in
            selectedString = 0 // Reset to first string when changing tuning
        }
        .alert("Microphone Permission", isPresented: $showPermissionAlert) {
            Button("OK") { }
        } message: {
            Text("Please allow microphone access in Settings to use the tuner.")
        }
    }
    
    private func startListening() {
        audioEngine.requestMicrophonePermission { granted in
            if granted {
                audioEngine.startRecording()
                isListening = true
            } else {
                showPermissionAlert = true
            }
        }
    }
    
    private func updatePenguinState(currentFrequency: Double, targetFrequency: Double) {
        // Cancel existing timer
        delayTimer?.invalidate()
        
        guard currentFrequency > 0 else {
            // Set timer to return to waiting state after 2 seconds
            delayTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                penguinState = .waiting
            }
            return
        }
        
        let cents = 1200 * log2(currentFrequency / targetFrequency)
        
        if abs(cents) < 5 {
            penguinState = .correct
        } else if cents < 0 {
            penguinState = .tooLow
        } else {
            penguinState = .tooHigh
        }
    }
}

enum PenguinState {
    case waiting
    case tooLow
    case correct
    case tooHigh
}

struct GuitarString {
    let note: String
    let octave: Int
    let frequency: Double
    
    var displayName: String {
        "\(note)\(octave)"
    }
}

#Preview {
    ContentView()
}
