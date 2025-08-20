//
//  AudioKitPitchTuner.swift
//  Pitch Penguin
//
//  Proven AudioKit PitchTap-based tuner implementation
//

import SwiftUI
import AudioKit
import SoundpipeAudioKit
import AVFoundation

// MARK: - ToneGenerator Class

class ToneGenerator {
    private let engine = AudioEngine()
    private let oscillator: Oscillator
    private let envelope: AmplitudeEnvelope
    
    init() {
        oscillator = Oscillator(waveform: Table(.sine), amplitude: 0.5)
        envelope = AmplitudeEnvelope(oscillator)
        envelope.attackDuration = 0.01
        envelope.decayDuration = 0.1
        envelope.sustainLevel = 0.1
        envelope.releaseDuration = 0.2
        
        engine.output = envelope
        
        do {
            try engine.start()
        } catch {
            print("❌ ToneGenerator Engine failed to start: \(error)")
        }
    }
    
    func play(frequency: Double, duration: TimeInterval = 0.5) {
        oscillator.frequency = AUValue(frequency)
        envelope.open()
        
        // Stop after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.envelope.close()
        }
    }
}


final class AudioKitPitchTuner: ObservableObject {
    // MARK: - Published Properties
    @Published var frequency: Float = 0
    @Published var amplitude: Float = 0
    @Published var isRecording = false
    @Published var currentNote: String = "--"
    @Published var cents: Int = 0
    @Published var detectedString: Int? = nil
    @Published var confidence: Float = 0
    
    // MARK: - Callbacks
    var getTargetFrequency: (() -> Double)?
    var getCurrentMode: (() -> Mode)? = { .auto }
    enum Mode { case auto, manual }
    
    // MARK: - Audio Properties
    private let engine = AudioEngine()
    private var pitchTap: PitchTap?
    private var mixer: Mixer?
    private let toneGenerator = ToneGenerator() // Add this
    
    // MARK: - Processing Settings
    private let minimumAmplitude: Float = 0.01
    private let updateInterval: TimeInterval = 0.05 // 50ms updates
    private var updateTimer: Timer?
    
    // MARK: - Frequency Smoothing
    private var frequencyBuffer: [Float] = []
    private let bufferSize = 20
    private var smoothedFrequency: Float = 0
    private var consecutiveStableReadings = 0
    
    // MARK: - Guitar Strings
    private let guitarStrings: [(note: String, octave: Int, frequency: Float)] = [
        ("E", 2, 82.41),
        ("A", 2, 110.00),
        ("D", 3, 146.83),
        ("G", 3, 196.00),
        ("B", 3, 246.94),
        ("E", 4, 329.63)
    ]
    
    // MARK: - Note Names
    private let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private let a4Frequency: Float = 440.0
    
    // MARK: - Initialization
    init() {
        setupAudioSession()
        setupAudioEngine()
    }
    
    deinit {
        stopRecording()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setPreferredSampleRate(48000.0)
            try session.setPreferredIOBufferDuration(0.005) // 5ms buffer for low latency
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }
    
    private func setupAudioEngine() {
        guard let input = engine.input else {
            print("❌ AudioEngine input not available")
            return
        }
        
        // Create a mixer to connect input
        mixer = Mixer(input)
        
        // Set up PitchTap with callback
        pitchTap = PitchTap(mixer!) { [weak self] pitchArray, ampArray in
            guard let self = self else { return }
            
            // Use first channel (mono)
            let detectedPitch = pitchArray[0]
            let detectedAmplitude = ampArray[0]
            
            // Process if amplitude is sufficient
            if detectedAmplitude > self.minimumAmplitude {
                self.processPitch(detectedPitch, amplitude: detectedAmplitude)
            } else {
                self.processSilence()
            }
        }
        
        // Connect mixer to output
        engine.output = mixer
    }
    
    // MARK: - Tone Generator Control
    func playTone(frequency: Double) {
        toneGenerator.play(frequency: frequency)
    }
    
    // MARK: - Recording Control
    func startRecording() {
        guard !isRecording else { return }
        
        do {
            // Activate audio session
            try AVAudioSession.sharedInstance().setActive(true)
            
            // Start the audio engine
            try engine.start()
            
            // Start pitch detection
            pitchTap?.start()
            
            isRecording = true
            resetState()
            
            // Start update timer for UI
            updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
                self?.updateUI()
            }
            
            print("🎸 AudioKit PitchTap Tuner started")
            
        } catch {
            print("❌ Failed to start: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        // Stop pitch detection
        pitchTap?.stop()
        
        // Stop the engine
        engine.stop()
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch { }
        
        // Stop update timer
        updateTimer?.invalidate()
        updateTimer = nil
        
        isRecording = false
        resetState()
        
        print("🛑 AudioKit PitchTap Tuner stopped")
    }
    
    private func resetState() {
        frequency = 0
        amplitude = 0
        currentNote = "--"
        cents = 0
        detectedString = nil
        confidence = 0
        frequencyBuffer.removeAll()
        smoothedFrequency = 0
        consecutiveStableReadings = 0
    }
    
    // MARK: - Pitch Processing
    private func processPitch(_ pitch: Float, amplitude: Float) {
        // Validate frequency range for guitar (50Hz to 400Hz with some margin)
        guard pitch > 50 && pitch < 450 else {
            processSilence()
            return
        }
        
        // Add to buffer
        frequencyBuffer.append(pitch)
        if frequencyBuffer.count > bufferSize {
            frequencyBuffer.removeFirst()
        }
        
        // Need minimum samples
        guard frequencyBuffer.count >= 3 else {
            return
        }
        
        // Calculate median for stability
        let sorted = frequencyBuffer.sorted()
        let median = sorted[sorted.count / 2]
        
        // Check for stability
        let variance = frequencyBuffer.map { pow($0 - median, 2) }.reduce(0, +) / Float(frequencyBuffer.count)
        let standardDeviation = sqrt(variance)
        
        // Consider stable if standard deviation is low
        let isStable = standardDeviation < 5.0
        
        if isStable {
            consecutiveStableReadings += 1
        } else {
            consecutiveStableReadings = 0
        }
        
        // Apply smoothing
        if smoothedFrequency == 0 {
            smoothedFrequency = median
        } else {
            // Heavier smoothing when stable
            let alpha: Float = isStable ? 0.9 : 0.5
            smoothedFrequency = alpha * smoothedFrequency + (1 - alpha) * median
        }
        
        // Store amplitude
        self.amplitude = amplitude
    }
    
    private func processSilence() {
        consecutiveStableReadings = 0
        
        // Slowly fade out
        if !frequencyBuffer.isEmpty {
            frequencyBuffer.removeLast()
        }
        
        if frequencyBuffer.isEmpty {
            smoothedFrequency = 0
            amplitude = 0
        }
    }
    
    // MARK: - UI Update
    private func updateUI() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.frequency = self.smoothedFrequency
            
            if self.smoothedFrequency > 0 {
                let noteData = self.frequencyToNote(self.smoothedFrequency)
                self.currentNote = "\(noteData.note)\(noteData.octave)"
                self.cents = noteData.cents
                self.detectedString = self.detectGuitarString(self.smoothedFrequency)
                
                // Confidence based on stability
                self.confidence = min(1.0, Float(self.consecutiveStableReadings) / 10.0)
                
                if self.consecutiveStableReadings > 5 {
                    print("✅ \(self.currentNote): \(String(format: "%.1f", self.smoothedFrequency))Hz (\(self.cents > 0 ? "+" : "")\(self.cents)¢)")
                } else {
                    print("🎸 \(self.currentNote): \(String(format: "%.1f", self.smoothedFrequency))Hz (\(self.cents > 0 ? "+" : "")\(self.cents)¢)")
                }
            } else {
                self.currentNote = "--"
                self.cents = 0
                self.detectedString = nil
                self.confidence = 0
            }
        }
    }
    
    // MARK: - Note Conversion
    private func frequencyToNote(_ frequency: Float) -> (note: String, octave: Int, cents: Int) {
        guard frequency > 0 else { return ("--", 0, 0) }
        
        // Calculate the nearest note and its cents deviation
        // This ensures cents is always relative to the nearest note, not a fixed reference
        let a4Freq: Float = 440.0
        let c0Freq: Float = a4Freq * pow(2, -4.75) // C0 = A4 * 2^(-57/12)
        
        // Calculate total semitones from C0
        let totalSemitones = 12.0 * log2(frequency / c0Freq)
        let nearestSemitone = round(totalSemitones)
        
        // Get the actual frequency of the nearest note
        let nearestNoteFreq = c0Freq * pow(2, nearestSemitone / 12.0)
        
        // Calculate cents relative to the nearest note
        let cents = Int(round(1200.0 * log2(frequency / nearestNoteFreq)))
        
        // Get note name and octave
        let midiNote = Int(nearestSemitone) + 12 // C0 = MIDI 12
        let noteIndex = midiNote % 12
        let octave = (midiNote / 12) - 1
        
        return (noteNames[noteIndex], octave, cents)
    }
    
    // MARK: - String Detection
    private func detectGuitarString(_ frequency: Float) -> Int? {
        guard frequency > 0 else { return nil }
        
        var closestString = 0
        var minCents: Float = Float.greatestFiniteMagnitude
        
        for (index, string) in guitarStrings.enumerated() {
            let cents = abs(1200 * log2(frequency / string.frequency))
            if cents < minCents {
                minCents = cents
                closestString = index
            }
        }
        
        // Only return if within 100 cents (1 semitone)
        return minCents < 100 ? closestString : nil
    }
}
