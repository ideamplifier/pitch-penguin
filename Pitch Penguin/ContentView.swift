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
    @State private var autoSelectDebounceTimer: Timer?
    @State private var pendingAutoSelect: Int?
    
    // Audio engine selection - Using proven AudioKit PitchTap
    @StateObject private var audioEngine = AudioKitPitchTuner()
    
    private var currentTuning: Tuning {
        let tunings = TuningData.getTunings(for: selectedInstrument)
        return tunings[selectedTuningIndex]
    }
    
    private var currentStrings: [GuitarString] {
        return currentTuning.notes
    }
    
    // MARK: - Note helpers
    private let NOTE_NAMES_SHARP = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    
    // Comprehensive note index mapping for all notations
    private let NOTE_INDEX: [String: Int] = [
        "C": 0, "C#": 1, "C♯": 1, "Db": 1, "D♭": 1,
        "D": 2, "D#": 3, "D♯": 3, "Eb": 3, "E♭": 3,
        "E": 4, "F": 5, "F#": 6, "F♯": 6, "Gb": 6, "G♭": 6,
        "G": 7, "G#": 8, "G♯": 8, "Ab": 8, "A♭": 8,
        "A": 9, "A#": 10, "A♯": 10, "Bb": 10, "B♭": 10,
        "B": 11
    ]
    
    private func posMod(_ x: Int, _ m: Int) -> Int {
        let r = x % m
        return r >= 0 ? r : r + m
    }
    
    private func hzToSemitoneOffset(from refHz: Double, to hz: Double) -> Double {
        return 12.0 * log2(hz / refHz)
    }
    
    /// Manual mode display calculation
    private func manualDisplay(detectedHz: Double,
                              baseNote: String,
                              baseOctave: Int,
                              a4: Double = 440.0) -> (name: String, cents: Double) {
        guard detectedHz > 0, let baseNoteIndex = NOTE_INDEX[baseNote] else { 
            return ("--", 0) 
        }
        
        // Calculate base frequency
        let baseMidi = 12 * (baseOctave + 1) + baseNoteIndex
        let f0 = a4 * pow(2.0, (Double(baseMidi) - 69.0) / 12.0)
        
        // Semitone offset from selected note
        let s = hzToSemitoneOffset(from: f0, to: detectedHz)
        
        // Limit to ±12 semitones (one octave) from selected note
        guard abs(s) <= 12 else {
            return ("--", 0)
        }
        
        var k = Int(round(s))
        var localCents = 100.0 * (s - Double(k))
        
        // Keep cents in [-50, +50] range
        if localCents <= -50.0 {
            k -= 1
            localCents += 100.0
        }
        if localCents > 50.0 {
            k += 1
            localCents -= 100.0
        }
        
        let labelIndex = posMod(baseNoteIndex + k, 12)
        let name = NOTE_NAMES_SHARP[labelIndex]
        return (name, localCents)
    }
    
    private var displayedNote: String {
        let freq = Double(audioEngine.frequency)
        
        if isAutoMode {
            guard freq > 0 else { return "--" }
            
            // Use NoteMath for consistent note calculation
            let noteNum = NoteMath.noteNumber(for: freq)
            
            // Limit to reasonable range for guitar/bass (E1 to E6)
            // E1 = MIDI 28, E6 = MIDI 88
            guard noteNum >= 28 && noteNum <= 88 else { return "--" }
            
            return NoteMath.name(forNote: noteNum)
        } else {
            // Manual mode: ALWAYS show the selected string's note
            guard let gs = currentStrings[safe: selectedString] else { return "--" }
            return gs.note  // Fixed note display
        }
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
                                  currentFrequency: Double(audioEngine.frequency),
                                  needlePosition: $currentNeedlePosition,
                                  directCents: isListening ? Double(audioEngine.cents) : nil)
                            .frame(height: 180)
                        
                        // Display detected note or selected note
                        VStack(spacing: 4) {
                            if isListening {
                                Text(displayedNote)
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                if audioEngine.frequency > 0, let targetFreq = currentStrings[safe: selectedString]?.frequency {
                                    let cents = 1200 * log2(Double(audioEngine.frequency) / targetFreq)
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
                        FrequencyDisplay(currentFrequency: Double(audioEngine.frequency),
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
                             currentFrequency: Double(audioEngine.frequency),
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
        .onAppear {
            // Set up target frequency callback
            audioEngine.getTargetFrequency = {
                return currentStrings[safe: selectedString]?.frequency ?? 0
            }
            // Set up mode callback
            audioEngine.getCurrentMode = { [self] in
                return isAutoMode ? .auto : .manual
            }
        }
        .onChange(of: audioEngine.frequency) { _, newValue in
            let frequency = Double(newValue)
            // Store last detected note
            if frequency > 0 {
                lastDetectedNote = displayedNote
                
                // Debug: Compare with target
                if let targetString = currentStrings[safe: selectedString] {
                    let cents = 1200 * log2(frequency / targetString.frequency)
                    let note = displayedNote
                    print("🎯 Target: \(targetString.note)\(targetString.octave) (\(String(format: "%.2f", targetString.frequency)) Hz)")
                    print("📍 Current: \(note) (\(String(format: "%.2f", frequency)) Hz)")
                    print("📏 Difference: \(String(format: "%+.1f", cents)) cents")
                    print("---")
                }
            }
            
            // Auto select string if in auto mode
            if isAutoMode && frequency > 0 {
                autoSelectString(frequency: frequency)
            }
            
            // Update accuracy states for all strings
            updateStringAccuracyStates(currentFrequency: frequency)
            
            if let targetFreq = currentStrings[safe: selectedString]?.frequency {
                updatePenguinState(currentFrequency: frequency, targetFrequency: targetFreq)
            }
        }
        .onChange(of: selectedString) { _, _ in
            // Update target frequency when string changes
            audioEngine.getTargetFrequency = {
                return currentStrings[safe: selectedString]?.frequency ?? 0
            }
        }
        .onChange(of: isAutoMode) { _, _ in
            // Update mode and target
            // audioEngine.mode = isAutoMode ? .auto : .manual
            // audioEngine.manualTargetHz = isAutoMode ? nil : currentStrings[safe: selectedString]?.frequency
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
        
        audioEngine.startRecording()
        DispatchQueue.main.async {
            self.isListening = true
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
        // Use AutoStringSelector from NoteMath
        let newString = AutoStringSelector.pickString(for: frequency, prevLocked: selectedString)
        
        // 현재 현과 다르면 디바운싱 적용
        if newString != selectedString {
            // 이전 타이머 취소
            autoSelectDebounceTimer?.invalidate()
            
            // 동일한 현이 0.5초 동안 유지되어야 변경 (더 안정적으로)
            pendingAutoSelect = newString
            autoSelectDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                // 여전히 같은 현을 가리키고 있으면 변경
                let currentNewString = AutoStringSelector.pickString(
                    for: Double(self.audioEngine.frequency), 
                    prevLocked: self.selectedString
                )
                if currentNewString == self.pendingAutoSelect {
                    self.selectedString = currentNewString
                    print("🎸 Auto-selected string \(currentNewString): \(self.currentStrings[currentNewString].note)\(self.currentStrings[currentNewString].octave)")
                }
                self.pendingAutoSelect = nil
            }
        } else {
            // 같은 현이면 타이머 취소
            autoSelectDebounceTimer?.invalidate()
            pendingAutoSelect = nil
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
