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
    @State private var delayTimer: Timer?
    @State private var selectedInstrument: InstrumentType = .guitar
    @State private var selectedTuningIndex = 0
    @State private var stringAccuracyStates: [Bool] = Array(repeating: false, count: 6)
    @State private var isAutoMode = true
    @State private var lastDetectedNote: String = ""
    @State private var currentNeedlePosition: Double = 0  // Track needle position
    
    @StateObject private var audioEngine = AudioEngine()
    
    private var currentTuning: Tuning {
        let tunings = TuningData.getTunings(for: selectedInstrument)
        return tunings[selectedTuningIndex]
    }
    
    private var currentStrings: [GuitarString] {
        return currentTuning.notes
    }
    
    private func posMod(_ x: Int, _ m: Int) -> Int {
        let r = x % m
        return r >= 0 ? r : r + m
    }
    
    private var detectedNote: String {
        guard audioEngine.detectedFrequency > 0 else { return "--" }
        
        let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        
        // Auto mode: find closest note absolutely
        if isAutoMode {
            let A4 = 440.0
            let midi = 69.0 + 12.0 * log2(audioEngine.detectedFrequency / A4)
            let nearest = Int(round(midi))
            let nameIndex = posMod(nearest, 12)
            return noteNames[nameIndex]
        }
        
        // Manual mode: Use needle position to determine note
        guard let selectedNote = currentStrings[safe: selectedString] else { return "--" }
        
        // Get note index for selected string
        let noteMap: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let baseNoteIndex = noteMap[selectedNote.note] else { return "--" }
        
        // Use needle position instead of frequency
        // Needle position is in degrees, where each semitone ≈ 9 degrees (since ±45° = ±5 semitones)
        let semitonesFromCenter = Int(round(currentNeedlePosition / 9.0))
        
        // Calculate label index based on needle position
        let labelIndex = posMod(baseNoteIndex + semitonesFromCenter, 12)
        
        return noteNames[labelIndex]
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
                                  currentFrequency: audioEngine.detectedFrequency,
                                  needlePosition: $currentNeedlePosition)
                            .frame(height: 180)
                        
                        // Display detected note or selected note
                        VStack(spacing: 4) {
                            if isListening {
                                Text(detectedNote)
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                if audioEngine.detectedFrequency > 0, let targetFreq = currentStrings[safe: selectedString]?.frequency {
                                    let cents = 1200 * log2(audioEngine.detectedFrequency / targetFreq)
                                    Text(String(format: "%+.0f cents", cents))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .offset(y: -2)
                                }
                            } else if !isAutoMode {
                                // Show last detected note or selected note when not listening and not in auto mode
                                if !lastDetectedNote.isEmpty {
                                    Text(lastDetectedNote)
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(.primary.opacity(0.5))
                                } else if let selectedNote = currentStrings[safe: selectedString] {
                                    Text(selectedNote.note)
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(.primary.opacity(0.5))
                                }
                            }
                        }
                        .offset(y: -152)
                    }
                    
                    Button(action: {
                        if isListening {
                            stopListening()
                        } else {
                            startListening()
                        }
                    }) {
                        PenguinView(state: penguinState)
                            .frame(width: 120, height: 120)
                            .offset(y: 3)
                    }
                }
                .padding(.vertical, 20)
                .offset(y: 80)
                
                VStack {
                    if isListening {
                        FrequencyDisplay(currentFrequency: audioEngine.detectedFrequency,
                                       targetFrequency: currentStrings[safe: selectedString]?.frequency ?? 0,
                                       isAutoMode: isAutoMode,
                                       needlePosition: currentNeedlePosition)
                            .onTapGesture {
                                stopListening()
                            }
                    } else {
                        VStack(spacing: 15) {
                            Text("Tap to start")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                                .frame(height: 34)
                            
                            Spacer()
                                .frame(height: 46) // Current/Target 부분 높이 차지
                        }
                        .onTapGesture {
                            startListening()
                        }
                    }
                }
                .frame(height: 80) // 고정 높이
                .padding(.top, 30)
                .offset(y: 10)
                
                Spacer()
                
                // Auto mode toggle button
                Button(action: {
                    isAutoMode.toggle()
                }) {
                    Text("Auto")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isAutoMode ? Color(red: 0.95, green: 0.92, blue: 0.88) : .primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isAutoMode ? Color(red: 0.055, green: 0.059, blue: 0.063) : Color.gray.opacity(0.1))
                        )
                }
                .padding(.bottom, 10)
                .offset(y: -20)
                
                StringSelector(selectedString: $selectedString, 
                             strings: currentStrings,
                             accuracyStates: stringAccuracyStates,
                             currentFrequency: audioEngine.detectedFrequency,
                             isDisabled: isAutoMode)
                    .padding(.horizontal)
                    .offset(y: -20)
                    .opacity(isAutoMode ? 0.3 : 1.0)
                
                InstrumentSelector(selectedInstrument: $selectedInstrument, 
                                 selectedTuningIndex: $selectedTuningIndex)
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                    .offset(y: -20)
            }
        }
        .onChange(of: audioEngine.detectedFrequency) { _, newValue in
            // Store last detected note
            if newValue > 0 {
                lastDetectedNote = detectedNote
            }
            
            // Auto select string if in auto mode
            if isAutoMode && newValue > 0 {
                autoSelectString(frequency: newValue)
            }
            
            // Update accuracy states for all strings
            updateStringAccuracyStates(currentFrequency: newValue)
            
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
        // Check if already recording to prevent duplicate starts
        guard !audioEngine.isRecording else { 
            print("Already recording, skipping startListening")
            return 
        }
        
        // Clear last detected note when starting
        lastDetectedNote = ""
        
        audioEngine.requestMicrophonePermission { granted in
            if granted {
                audioEngine.startRecording()
                DispatchQueue.main.async {
                    self.isListening = true
                }
            } else {
                DispatchQueue.main.async {
                    self.showPermissionAlert = true
                }
            }
        }
    }
    
    private func stopListening() {
        audioEngine.stopRecording()
        isListening = false
        penguinState = .waiting
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
        
        // Use needle position instead of cents
        if abs(currentNeedlePosition) < 5 {
            penguinState = .correct
        } else if currentNeedlePosition < 0 {
            penguinState = .tooLow
        } else {
            penguinState = .tooHigh
        }
    }
    
    private func autoSelectString(frequency: Double) {
        var closestString = 0
        var minCentsDiff = Double.infinity
        
        for (index, string) in currentStrings.enumerated() {
            let cents = abs(1200 * log2(frequency / string.frequency))
            if cents < minCentsDiff && cents < 50 { // Within 50 cents
                minCentsDiff = cents
                closestString = index
            }
        }
        
        // Only change if significantly closer to another string
        if closestString != selectedString && minCentsDiff < 30 {
            selectedString = closestString
        }
    }
    
    private func updateStringAccuracyStates(currentFrequency: Double) {
        guard currentFrequency > 0 else {
            stringAccuracyStates = Array(repeating: false, count: currentStrings.count)
            return
        }
        
        for (index, string) in currentStrings.enumerated() {
            let cents = abs(1200 * log2(currentFrequency / string.frequency))
            stringAccuracyStates[safe: index] = cents < 5
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
