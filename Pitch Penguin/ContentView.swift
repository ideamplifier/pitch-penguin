//
//  ContentView.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @State private var selectedString = 0
    @State private var isListening = false
    @State private var penguinState: PenguinState = .waiting
    @State private var showPermissionAlert = false
    @State private var delayTimer: Timer?
    @State private var selectedInstrument: InstrumentType = .guitar
    @State private var selectedTuningIndex = 0
    @State private var stringAccuracyStates: [Bool] = Array(repeating: false, count: 6)
    @State private var lastDetectedNote: String = ""
    @State private var currentNeedlePosition: Double = 0
    @State private var autoSelectDebounceTimer: Timer?
    @State private var pendingAutoSelect: Int?

    @StateObject private var audioEngine = AudioKitPitchTuner()

    private var currentTuning: Tuning {
        let tunings = TuningData.getTunings(for: selectedInstrument)
        return tunings[safe: selectedTuningIndex] ?? TuningData.guitarTunings[0]
    }

    private var currentStrings: [GuitarString] {
        return currentTuning.notes
    }

    private var displayedNote: String {
        let freq = Double(audioEngine.frequency)

        guard freq > 0 else { return "--" }
        let noteNum = NoteMath.noteNumber(for: freq)
        guard noteNum >= 28 && noteNum <= 88 else { return "--" }
        return NoteMath.name(forNote: noteNum)
    }

    var body: some View {
        ZStack {
            Color(red: 0.95, green: 0.92, blue: 0.88).ignoresSafeArea()

            MainView(
                selectedString: $selectedString,
                isListening: $isListening,
                penguinState: $penguinState,
                selectedInstrument: $selectedInstrument,
                selectedTuningIndex: $selectedTuningIndex,
                stringAccuracyStates: $stringAccuracyStates,
                lastDetectedNote: $lastDetectedNote,
                currentNeedlePosition: $currentNeedlePosition,
                audioEngine: audioEngine,
                currentTuning: currentTuning,
                currentStrings: currentStrings,
                displayedNote: displayedNote,
                startListening: startListening,
                stopListening: stopListening
            )
        }
        .onAppear(perform: setupCallbacks)
        .onChange(of: audioEngine.frequency) { _, newValue in handleFrequencyChange(newValue) }
        .onChange(of: selectedString) { _, _ in updateTargetFrequency() }
        .onChange(of: selectedInstrument) { _, _ in selectedString = 0 }
        .onChange(of: selectedTuningIndex) { _, _ in selectedString = 0 }
        .alert("Microphone Permission", isPresented: $showPermissionAlert) {
            Button("OK") {}
        } message: {
            Text("Please allow microphone access in Settings to use the tuner.")
        }
    }

    // MARK: - Methods

    private func setupCallbacks() {
        updateTargetFrequency()
        audioEngine.getCurrentMode = { .auto }
    }

    private func handleFrequencyChange(_ newValue: Float) {
        let frequency = Double(newValue)
        if frequency > 0 {
            lastDetectedNote = displayedNote
        }

        if frequency > 0 {
            autoSelectString(frequency: frequency)
        }

        updateStringAccuracyStates(currentFrequency: frequency)

        if let targetFreq = currentStrings[safe: selectedString]?.frequency {
            updatePenguinState(currentFrequency: frequency, targetFrequency: targetFreq)
        }
    }

    private func updateTargetFrequency() {
        audioEngine.getTargetFrequency = { currentStrings[safe: selectedString]?.frequency ?? 0 }
    }

    private func startListening() {
        guard !audioEngine.isRecording else { return }
        lastDetectedNote = ""
        audioEngine.startRecording()
        isListening = true
    }

    private func stopListening() {
        audioEngine.stopRecording()
        isListening = false
        penguinState = .waiting
    }

    private func updatePenguinState(currentFrequency: Double, targetFrequency _: Double) {
        delayTimer?.invalidate()
        guard currentFrequency > 0 else {
            delayTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                penguinState = .waiting
            }
            return
        }

        if abs(currentNeedlePosition) < 5 {
            penguinState = .correct
        } else if currentNeedlePosition < 0 {
            penguinState = .tooLow
        } else {
            penguinState = .tooHigh
        }
    }

    private func autoSelectString(frequency: Double) {
        let newString = AutoStringSelector.pickString(for: frequency, prevLocked: selectedString)
        if newString != selectedString {
            autoSelectDebounceTimer?.invalidate()
            pendingAutoSelect = newString
            autoSelectDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                let currentNewString = AutoStringSelector.pickString(for: Double(self.audioEngine.frequency), prevLocked: self.selectedString)
                if currentNewString == self.pendingAutoSelect {
                    self.selectedString = currentNewString
                }
                self.pendingAutoSelect = nil
            }
        } else {
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

// MARK: - MainView (Refactored)

private struct MainView: View {
    @Binding var selectedString: Int
    @Binding var isListening: Bool
    @Binding var penguinState: PenguinState
    @Binding var selectedInstrument: InstrumentType
    @Binding var selectedTuningIndex: Int
    @Binding var stringAccuracyStates: [Bool]
    @Binding var lastDetectedNote: String
    @Binding var currentNeedlePosition: Double

    @ObservedObject var audioEngine: AudioKitPitchTuner
    let currentTuning: Tuning
    let currentStrings: [GuitarString]
    let displayedNote: String

    let startListening: () -> Void
    let stopListening: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Text("Pitch Penguin")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 40)

            TunerDisplay(
                isListening: $isListening,
                audioEngine: audioEngine,
                currentStrings: currentStrings,
                selectedString: selectedString,
                currentNeedlePosition: $currentNeedlePosition,
                penguinState: $penguinState,
                displayedNote: displayedNote,
                lastDetectedNote: lastDetectedNote,
                onStartStop: {
                    if isListening { stopListening() } else { startListening() }
                }
            )

            FrequencyDisplayWrapper(
                isListening: isListening,
                audioEngine: audioEngine,
                targetFrequency: currentStrings[safe: selectedString]?.frequency ?? 0,
                currentNeedlePosition: currentNeedlePosition,
                onStart: startListening,
                onStop: stopListening
            )

            Spacer()

            ControlsView(
                selectedString: $selectedString,
                strings: currentStrings,
                accuracyStates: stringAccuracyStates,
                audioEngine: audioEngine,
                selectedInstrument: $selectedInstrument,
                selectedTuningIndex: $selectedTuningIndex
            )
        }
    }
}

// MARK: - Subviews

private struct TunerDisplay: View {
    @Binding var isListening: Bool
    @ObservedObject var audioEngine: AudioKitPitchTuner
    let currentStrings: [GuitarString]
    let selectedString: Int
    @Binding var currentNeedlePosition: Double
    @Binding var penguinState: PenguinState
    let displayedNote: String
    let lastDetectedNote: String
    let onStartStop: () -> Void

    var body: some View {
        VStack(spacing: -80) {
            ZStack {
                TuningMeter(
                    targetFrequency: currentStrings[safe: selectedString]?.frequency ?? 0,
                    currentFrequency: Double(audioEngine.frequency),
                    needlePosition: $currentNeedlePosition,
                    directCents: isListening ? Double(audioEngine.cents) : nil
                )
                .frame(height: 180)

                NoteDisplay(
                    isListening: isListening,
                    displayedNote: displayedNote,
                    lastDetectedNote: lastDetectedNote,
                    selectedNote: currentStrings[safe: selectedString],
                    frequency: audioEngine.frequency,
                    cents: audioEngine.cents
                )
                .offset(y: -152)
            }

            Button(action: onStartStop) {
                PenguinView(state: penguinState)
                    .frame(width: 120, height: 120)
                    .offset(y: 3)
            }
        }
        .padding(.vertical, 20)
        .offset(y: 80)
    }
}

private struct NoteDisplay: View {
    let isListening: Bool
    let displayedNote: String
    let lastDetectedNote: String
    let selectedNote: GuitarString?
    let frequency: Float
    let cents: Int

    var body: some View {
        VStack(spacing: 4) {
            if isListening {
                Text(displayedNote)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.primary)

            } else {
                let noteToShow = !lastDetectedNote.isEmpty ? lastDetectedNote : (selectedNote?.note ?? "")
                Text(noteToShow)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.primary.opacity(0.5))
            }
        }
    }
}

private struct FrequencyDisplayWrapper: View {
    let isListening: Bool
    @ObservedObject var audioEngine: AudioKitPitchTuner
    let targetFrequency: Double
    let currentNeedlePosition: Double
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack {
            if isListening {
                FrequencyDisplay(
                    currentFrequency: Double(audioEngine.frequency),
                    targetFrequency: targetFrequency,
                    needlePosition: currentNeedlePosition
                )
                .onTapGesture(perform: onStop)
            } else {
                VStack(spacing: 15) {
                    Text("Tap to start")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                        .frame(height: 34)

                    Spacer().frame(height: 46)
                }
                .onTapGesture(perform: onStart)
            }
        }
        .frame(height: 80)
        .padding(.top, 30)
        .offset(y: 10)
    }
}

private struct ControlsView: View {
    @Binding var selectedString: Int
    let strings: [GuitarString]
    let accuracyStates: [Bool]
    @ObservedObject var audioEngine: AudioKitPitchTuner
    @Binding var selectedInstrument: InstrumentType
    @Binding var selectedTuningIndex: Int

    var body: some View {
        VStack(spacing: 0) {
            StringSelector(
                strings: strings
            )
            .environmentObject(audioEngine)
            .padding(.horizontal)
            .offset(y: -10)

            InstrumentSelector(
                selectedInstrument: $selectedInstrument,
                selectedTuningIndex: $selectedTuningIndex
            )
            .padding(.horizontal)
            .padding(.bottom, 30)
            .offset(y: 15)
        }
        .offset(y: -25)
    }
}

// MARK: - Helper Structs & Enums

enum PenguinState {
    case waiting, tooLow, correct, tooHigh
}

struct GuitarString: Identifiable {
    let id = UUID()
    let note: String
    let octave: Int
    let frequency: Double

    var displayName: String { "\(note)\(octave)" }
}

#Preview {
    ContentView()
}