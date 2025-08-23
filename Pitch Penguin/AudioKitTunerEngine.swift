//
//  AudioKitTunerEngine.swift
//  Pitch Penguin
//
//  Professional tuner using AudioKit's proven pitch detection
//

import AudioKit
import AVFoundation
import SoundpipeAudioKit
import SwiftUI

final class AudioKitTunerEngine: ObservableObject {
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

    // MARK: - AudioKit Properties

    private let engine = AudioEngine()
    private var mic: AudioEngine.InputNode?
    private var tracker: PitchTap?
    private var silence: Mixer?

    // MARK: - Processing Settings

    private let minAmplitude: Float = 0.01
    private let smoothingFactor: Float = 0.85
    private var lastFrequency: Float = 0

    // MARK: - Frequency Buffer for Smoothing

    private var frequencyBuffer: [Float] = []
    private let bufferSize = 5

    // MARK: - Guitar String Definitions

    private let guitarStrings: [(note: String, octave: Int, frequency: Float)] = [
        ("E", 2, 82.41),
        ("A", 2, 110.00),
        ("D", 3, 146.83),
        ("G", 3, 196.00),
        ("B", 3, 246.94),
        ("E", 4, 329.63),
    ]

    // MARK: - Note Names

    private let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private let a4Frequency: Float = 440.0

    // MARK: - Initialization

    init() {
        setupAudioKit()
    }

    private func setupAudioKit() {
        // Configure audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setPreferredSampleRate(48000)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("Failed to setup audio session: \(error)")
            #endif
        }

        // Setup AudioKit
        guard let input = engine.input else {
            #if DEBUG
            print("AudioKit: No input available")
            #endif
            return
        }

        mic = input

        // Create a silent output (we only need input for tuning)
        silence = Mixer(input)
        silence?.volume = 0
        engine.output = silence
    }

    // MARK: - Recording Control

    func startRecording() {
        guard !isRecording else { return }

        guard let mic = mic else {
            #if DEBUG
            print("No microphone available")
            #endif
            return
        }

        // Create pitch tracker with optimized settings
        tracker = PitchTap(mic, handler: { [weak self] pitch, amp in
            self?.processPitch(pitch: pitch, amplitude: amp)
        })

        // Start the engine and tracker
        do {
            try engine.start()
            tracker?.start()
            isRecording = true

            // Reset state
            lastFrequency = 0
            frequencyBuffer.removeAll()

            #if DEBUG
            print("🎸 AudioKit Tuner started successfully")
            #endif

        } catch {
            #if DEBUG
            print("AudioKit failed to start: \(error)")
            #endif
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        tracker?.stop()
        engine.stop()

        isRecording = false

        // Reset published values
        DispatchQueue.main.async {
            self.frequency = 0
            self.amplitude = 0
            self.currentNote = "--"
            self.cents = 0
            self.detectedString = nil
            self.confidence = 0
        }

        #if DEBUG
        print("🛑 AudioKit Tuner stopped")
        #endif
    }

    // MARK: - Pitch Processing

    private func processPitch(pitch: [Float], amplitude: [Float]) {
        // Get the first (most prominent) pitch
        guard let detectedPitch = pitch.first,
              let detectedAmplitude = amplitude.first else { return }

        // Filter out silence
        guard detectedAmplitude > minAmplitude else {
            handleSilence()
            return
        }

        // Filter out unrealistic frequencies
        guard detectedPitch > 60, detectedPitch < 2000 else {
            return
        }

        // Apply smoothing
        let smoothedFrequency = applySmoothing(detectedPitch)

        // Calculate confidence based on amplitude
        let calculatedConfidence = min(1.0, detectedAmplitude * 10)

        // Update UI on main thread
        updateUI(frequency: smoothedFrequency,
                 amplitude: detectedAmplitude,
                 confidence: calculatedConfidence)
    }

    // MARK: - Smoothing

    private func applySmoothing(_ frequency: Float) -> Float {
        // Add to buffer
        frequencyBuffer.append(frequency)
        if frequencyBuffer.count > bufferSize {
            frequencyBuffer.removeFirst()
        }

        // If buffer is not full, return current frequency
        guard frequencyBuffer.count >= bufferSize else {
            lastFrequency = frequency
            return frequency
        }

        // Remove outliers using median filter
        let sorted = frequencyBuffer.sorted()
        let median = sorted[bufferSize / 2]

        // Apply exponential smoothing to median
        if lastFrequency == 0 {
            lastFrequency = median
        } else {
            // Check for large jumps (possible octave error)
            let ratio = median / lastFrequency
            if ratio > 1.8 && ratio < 2.2 {
                // Likely octave jump, ignore
                return lastFrequency
            } else if ratio > 0.45 && ratio < 0.55 {
                // Likely octave drop, ignore
                return lastFrequency
            }

            // Normal smoothing
            lastFrequency = smoothingFactor * lastFrequency + (1 - smoothingFactor) * median
        }

        return lastFrequency
    }

    // MARK: - Handle Silence

    private func handleSilence() {
        // Gradually reduce frequency buffer
        if !frequencyBuffer.isEmpty {
            frequencyBuffer.removeFirst()
        }

        // If silent for too long, reset
        if frequencyBuffer.isEmpty {
            DispatchQueue.main.async {
                self.frequency = 0
                self.amplitude = 0
                self.currentNote = "--"
                self.cents = 0
                self.detectedString = nil
                self.confidence = 0
            }
            lastFrequency = 0
        }
    }

    // MARK: - Note Conversion

    private func frequencyToNote(_ frequency: Float) -> (note: String, octave: Int, cents: Int) {
        guard frequency > 0 else { return ("--", 0, 0) }

        let semitones = 12.0 * log2(frequency / a4Frequency)
        let roundedSemitones = round(semitones)
        let cents = Int(round((semitones - roundedSemitones) * 100))

        let noteIndex = (Int(roundedSemitones) + 9 + 1200) % 12
        let octave = 4 + Int((roundedSemitones + 9) / 12)

        return (noteNames[noteIndex], octave, cents)
    }

    // MARK: - UI Update

    private func updateUI(frequency: Float, amplitude: Float, confidence: Float) {
        DispatchQueue.main.async {
            self.frequency = frequency
            self.amplitude = amplitude
            self.confidence = confidence

            if frequency > 0 {
                let noteData = self.frequencyToNote(frequency)
                self.currentNote = "\(noteData.note)\(noteData.octave)"
                self.cents = noteData.cents
                self.detectedString = self.detectGuitarString(frequency)

                // Debug output
                #if DEBUG
                print("🎵 \(self.currentNote): \(String(format: "%.1f", frequency))Hz (\(self.cents > 0 ? "+" : "")\(self.cents)¢) [Amp: \(String(format: "%.3f", amplitude))]")
                #endif
            } else {
                self.currentNote = "--"
                self.cents = 0
                self.detectedString = nil
            }
        }
    }

    private func detectGuitarString(_ frequency: Float) -> Int? {
        guard frequency > 0 else { return nil }

        var closestString = 0
        var minCents = Float.greatestFiniteMagnitude

        for (index, string) in guitarStrings.enumerated() {
            let cents = abs(1200 * log2(frequency / string.frequency))
            if cents < minCents {
                minCents = cents
                closestString = index
            }
        }

        return minCents < 100 ? closestString : nil
    }
}
