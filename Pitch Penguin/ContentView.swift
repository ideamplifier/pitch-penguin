//
//  ContentView.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedString = 0
    @State private var isListening = false
    @State private var penguinState: PenguinState = .waiting
    @State private var showPermissionAlert = false
    
    @StateObject private var audioEngine = AudioEngine()
    
    let guitarStrings = [
        GuitarString(note: "E", octave: 2, frequency: 82.41),
        GuitarString(note: "A", octave: 2, frequency: 110.00),
        GuitarString(note: "D", octave: 3, frequency: 146.83),
        GuitarString(note: "G", octave: 3, frequency: 196.00),
        GuitarString(note: "B", octave: 3, frequency: 246.94),
        GuitarString(note: "E", octave: 4, frequency: 329.63)
    ]
    
    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.92, blue: 0.88)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("Pitch Penguin")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 40)
                
                StringSelector(selectedString: $selectedString, strings: guitarStrings)
                    .padding(.horizontal)
                
                ZStack {
                    TuningMeter(targetFrequency: guitarStrings[selectedString].frequency,
                              currentFrequency: audioEngine.detectedFrequency)
                        .frame(height: 180)
                    
                    PenguinView(state: penguinState)
                        .frame(width: 120, height: 120)
                        .offset(y: 80)
                }
                .padding(.vertical, 20)
                
                FrequencyDisplay(currentFrequency: audioEngine.detectedFrequency,
                               targetFrequency: guitarStrings[selectedString].frequency)
                    .padding(.top, 30)
                
                Spacer()
                
                Button(action: toggleListening) {
                    Label(isListening ? "Stop" : "Start Tuning",
                          systemImage: isListening ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .padding()
                        .background(isListening ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.bottom, 40)
            }
        }
        .onChange(of: audioEngine.detectedFrequency) { _, newValue in
            updatePenguinState(currentFrequency: newValue, targetFrequency: guitarStrings[selectedString].frequency)
        }
        .alert("Microphone Permission", isPresented: $showPermissionAlert) {
            Button("OK") { }
        } message: {
            Text("Please allow microphone access in Settings to use the tuner.")
        }
    }
    
    private func toggleListening() {
        if isListening {
            audioEngine.stopRecording()
            isListening = false
            penguinState = .waiting
        } else {
            audioEngine.requestMicrophonePermission { granted in
                if granted {
                    audioEngine.startRecording()
                    isListening = true
                } else {
                    showPermissionAlert = true
                }
            }
        }
    }
    
    private func updatePenguinState(currentFrequency: Double, targetFrequency: Double) {
        guard currentFrequency > 0 else {
            penguinState = .waiting
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
