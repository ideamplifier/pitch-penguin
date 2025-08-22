//
//  AudioKitPitchTuner.swift
//  Pitch Penguin
//
//  Proven AudioKit PitchTap-based tuner implementation
//

import AudioKit
import AVFoundation
import SoundpipeAudioKit
import SwiftUI

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

    // MARK: - Audio Properties (Single Engine for both input and output)

    private let engine = AudioEngine()
    private var pitchTap: PitchTap?
    private var mixer: Mixer?

    // Tone Generator properties (within same engine)
    private let oscillator: Oscillator
    private let envelope: AmplitudeEnvelope

    // MARK: - Processing Settings

    private let minimumAmplitude: Float = 0.01
    private let updateInterval: TimeInterval = 0.05 // 50ms updates
    private var updateTimer: Timer?

    // MARK: - Frequency Smoothing

    private var frequencyBuffer: [Float] = []
    private let bufferSize = 20
    private var smoothedFrequency: Float = 0
    private var consecutiveStableReadings = 0

    // MARK: - Active Tuning
    @Published var activeTuning: Tuning


    // MARK: - Note Names

    private let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private let a4Frequency: Float = 440.0

    // MARK: - Initialization

    convenience init() {
        let standardTuning = Tuning(name: "Standard", notes: [
            GuitarString(note: "E", octave: 2, frequency: 82.41),
            GuitarString(note: "A", octave: 2, frequency: 110.00),
            GuitarString(note: "D", octave: 3, frequency: 146.83),
            GuitarString(note: "G", octave: 3, frequency: 196.00),
            GuitarString(note: "B", octave: 3, frequency: 246.94),
            GuitarString(note: "E", octave: 4, frequency: 329.63),
        ])
        self.init(tuning: standardTuning)
    }

    init(tuning: Tuning) {
        self.activeTuning = tuning
        // Initialize tone generator components
        oscillator = Oscillator(waveform: Table(.sine), amplitude: 0.5)
        envelope = AmplitudeEnvelope(oscillator)
        envelope.attackDuration = 0.01
        envelope.decayDuration = 0.1
        envelope.sustainLevel = 0.1
        envelope.releaseDuration = 0.2

        setupAudioSession()
        setupAudioEngine()
    }

    // MARK: - Public Methods

    func setTuning(_ newTuning: Tuning) {
        activeTuning = newTuning
    }

    deinit {
        stopRecording()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: []) // Removed .defaultToSpeaker
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }

    private func setupAudioEngine() {
        guard let input = engine.input else {
            print("❌ AudioEngine input not available")
            return
        }

        // Create mixer that combines input (for pitchTap) and oscillator (for tone generation)
        mixer = Mixer(input, envelope)

        // Set up PitchTap on the input
        pitchTap = PitchTap(input) { [weak self] pitchArray, ampArray in
            guard let self = self else { return }

            let detectedPitch = pitchArray[0]
            let detectedAmplitude = ampArray[0]

            if detectedAmplitude > self.minimumAmplitude {
                self.processPitch(detectedPitch, amplitude: detectedAmplitude)
            } else {
                self.processSilence()
            }
        }

        // Set mixer as output (handles both input monitoring and tone output)
        engine.output = mixer
    }

    // MARK: - Tone Generator Control

    func playTone(frequency: Double) {
        oscillator.frequency = AUValue(frequency)
        envelope.openGate()

        // Stop after duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.envelope.closeGate()
        }
    }

    // MARK: - Recording Control

    func startRecording() {
        guard !isRecording else { return }

        do {
            // Activate audio session
            try AVAudioSession.sharedInstance().setActive(true)

            // Start oscillator first (for tone generation)
            oscillator.start()

            // Start the single audio engine
            try engine.start()

            // Start pitch detection
            pitchTap?.start()

            isRecording = true
            resetState()

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

        pitchTap?.stop()
        oscillator.stop()
        engine.stop()

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {}

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
        guard pitch > 50, pitch < 450 else {
            processSilence()
            return
        }

        frequencyBuffer.append(pitch)
        if frequencyBuffer.count > bufferSize {
            frequencyBuffer.removeFirst()
        }

        guard frequencyBuffer.count >= 3 else {
            return
        }

        let sorted = frequencyBuffer.sorted()
        let median = sorted[sorted.count / 2]

        let variance = frequencyBuffer.map { pow($0 - median, 2) }.reduce(0, +) / Float(frequencyBuffer.count)
        let standardDeviation = sqrt(variance)

        let isStable = standardDeviation < 5.0

        if isStable {
            consecutiveStableReadings += 1
        } else {
            consecutiveStableReadings = 0
        }

        if smoothedFrequency == 0 {
            smoothedFrequency = median
        } else {
            let alpha: Float = isStable ? 0.9 : 0.5
            smoothedFrequency = alpha * smoothedFrequency + (1 - alpha) * median
        }

        self.amplitude = amplitude
    }

    private func processSilence() {
        consecutiveStableReadings = 0
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
                let chromaticNoteData = self.frequencyToChromaticNote(self.smoothedFrequency)
                self.currentNote = "\(chromaticNoteData.note)\(chromaticNoteData.octave)"
                
                if let detectedStringIndex = self.detectGuitarString(self.smoothedFrequency) {
                    self.detectedString = detectedStringIndex
                    let targetFrequency = self.activeTuning.notes[detectedStringIndex].frequency
                    self.cents = Int(round(1200.0 * log2(self.smoothedFrequency / Float(targetFrequency))))
                } else {
                    self.detectedString = nil
                    // If no string is detected, use the chromatic cents.
                    self.cents = chromaticNoteData.cents
                }

                self.confidence = min(1.0, Float(self.consecutiveStableReadings) / 10.0)

            } else {
                self.currentNote = "--"
                self.cents = 0
                self.detectedString = nil
                self.confidence = 0
            }
        }
    }

    // MARK: - Note Conversion

    private func frequencyToChromaticNote(_ frequency: Float) -> (note: String, octave: Int, cents: Int) {
        guard frequency > 0 else { return ("--", 0, 0) }

        let a4Freq: Float = 440.0
        let c0Freq: Float = a4Freq * pow(2, -4.75)
        let totalSemitones = 12.0 * log2(frequency / c0Freq)
        let nearestSemitone = round(totalSemitones)
        let nearestNoteFreq = c0Freq * pow(2, nearestSemitone / 12.0)
        let cents = Int(round(1200.0 * log2(frequency / nearestNoteFreq)))
        let midiNote = Int(nearestSemitone) + 12
        let noteIndex = midiNote % 12
        let octave = (midiNote / 12) - 1
        return (noteNames[noteIndex], octave, cents)
    }

    // MARK: - String Detection

    private func detectGuitarString(_ frequency: Float) -> Int? {
        guard frequency > 0, !activeTuning.notes.isEmpty else { return nil }

        var closestStringIndex: Int?
        var minCents: Float = .greatestFiniteMagnitude

        for (index, string) in activeTuning.notes.enumerated() {
            let centsDifference = abs(1200 * log2(frequency / Float(string.frequency)))
            if centsDifference < minCents {
                minCents = centsDifference
                closestStringIndex = index
            }
        }

        if minCents < 100 {
            return closestStringIndex
        }

        return nil
    }
}
