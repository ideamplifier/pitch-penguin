//
//  AudioKitTuner.swift
//  Pitch Penguin
//
//  Simple and reliable pitch detection using AudioKit
//

import SwiftUI
import AudioKit
import SoundpipeAudioKit
import AVFoundation

class AudioKitTuner: ObservableObject {
    @Published var frequency: Float = 0
    @Published var amplitude: Float = 0
    @Published var isRecording = false
    
    private let engine = AudioKit.AudioEngine()
    private var pitchTap: PitchTap?
    private var mic: AudioKit.AudioEngine.InputNode?
    
    // Frequency history for stabilization
    private var frequencyHistory: [Float] = []
    private let historySize = 5
    
    init() {
        setupAudio()
    }
    
    private func setupAudio() {
        guard let input = engine.input else {
            print("❌ AudioKit: No input available")
            return
        }
        
        mic = input
        
        // Setup pitch detection
        pitchTap = PitchTap(input) { [weak self] pitch, amp in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // Only update if amplitude is significant (reduce noise)
                if amp[0] > 0.01 {
                    self.updateFrequency(Float(pitch[0]))
                    self.amplitude = Float(amp[0])
                } else {
                    // Gradually decay when no signal
                    self.frequency *= 0.95
                    if self.frequency < 20 {
                        self.frequency = 0
                    }
                    self.amplitude = 0
                }
            }
        }
        
        engine.output = mic
    }
    
    private func updateFrequency(_ newFreq: Float) {
        // Add to history
        frequencyHistory.append(newFreq)
        if frequencyHistory.count > historySize {
            frequencyHistory.removeFirst()
        }
        
        // Use median for stability
        if frequencyHistory.count >= 3 {
            let sorted = frequencyHistory.sorted()
            let median = sorted[sorted.count / 2]
            
            // Check if values are consistent (within 5% of median)
            let consistent = frequencyHistory.allSatisfy { 
                abs($0 - median) / median < 0.05 
            }
            
            if consistent {
                frequency = median
            }
        } else {
            frequency = newFreq
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        // Request microphone permission
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                self?.handlePermissionResponse(granted)
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                self?.handlePermissionResponse(granted)
            }
        }
    }
    
    private func handlePermissionResponse(_ granted: Bool) {
        guard granted else {
            print("❌ Microphone permission denied")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                do {
                    // Configure audio session
                    try AVAudioSession.sharedInstance().setCategory(.playAndRecord, 
                                                                    mode: .measurement,
                                                                    options: [.defaultToSpeaker, .mixWithOthers])
                    try AVAudioSession.sharedInstance().setActive(true)
                    
                    // Start pitch detection
                    self.pitchTap?.start()
                    
                    // Start audio engine
                    try self.engine.start()
                    
                    self.isRecording = true
                    self.frequencyHistory.removeAll()
                    
                    print("✅ AudioKit started successfully")
                } catch {
                    print("❌ AudioKit failed to start: \(error)")
                }
            }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        pitchTap?.stop()
        engine.stop()
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        
        isRecording = false
        frequency = 0
        amplitude = 0
        frequencyHistory.removeAll()
        
        print("✅ AudioKit stopped")
    }
}

// Helper to calculate note from frequency
extension AudioKitTuner {
    func getNoteInfo(for frequency: Float) -> (note: String, cents: Float) {
        guard frequency > 0 else { return ("--", 0) }
        
        let A4 = Float(440.0)
        let C0 = A4 * pow(2, -4.75)
        
        if frequency > C0 {
            let halfStepsBelowA4 = 12 * log2(frequency / A4)
            let midiNote = Int(round(69 + halfStepsBelowA4))
            let nearestFreq = A4 * pow(2, Float(midiNote - 69) / 12)
            let cents = 1200 * log2(frequency / nearestFreq)
            
            let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
            let noteName = noteNames[midiNote % 12]
            let octave = (midiNote / 12) - 1
            
            return ("\(noteName)\(octave)", cents)
        }
        
        return ("--", 0)
    }
}