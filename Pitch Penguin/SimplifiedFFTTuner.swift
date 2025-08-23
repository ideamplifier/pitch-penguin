//
//  SimplifiedFFTTuner.swift
//  Pitch Penguin
//
//  Ultra-simple FFT-based tuner for maximum stability
//

import Accelerate
import AVFoundation
import SwiftUI

final class SimplifiedFFTTuner: ObservableObject {
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

    private let audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }
    private var sampleRate: Double = 48000.0

    // MARK: - FFT Properties

    private var fftSetup: FFTSetup?
    private let fftSize = 8192
    private var halfFFTSize: Int { fftSize / 2 }
    private var log2n: vDSP_Length { vDSP_Length(log2(Float(fftSize))) }

    // MARK: - Processing Settings

    private let minRMS: Float = 0.01
    private let bufferSize: AVAudioFrameCount = 8192

    // MARK: - Frequency Smoothing

    private var frequencyHistory: [Float] = []
    private let historyMaxSize = 10
    private var lastStableFrequency: Float = 0

    // MARK: - Guitar Strings

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
        setupFFT()
        setupAudio()
    }

    deinit {
        if let fftSetup = fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    private func setupFFT() {
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }

    private func setupAudio() {
        // Audio session setup will be done when recording starts
    }

    // MARK: - Recording Control

    func startRecording() {
        guard !isRecording else { return }

        let session = AVAudioSession.sharedInstance()

        switch session.recordPermission {
        case .granted:
            setupAndStartEngine(session: session)
        case .denied:
            #if DEBUG
            print("❌ Microphone permission denied. Please enable it in Settings.")
            #endif
            // Consider showing an alert to the user
            return
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupAndStartEngine(session: session)
                    } else {
                        #if DEBUG
                        print("❌ Microphone permission was not granted.")
                        #endif
                    }
                }
            }
        @unknown default:
            #if DEBUG
            print("❌ Unknown case for record permission")
            #endif
        }
    }

    private func setupAndStartEngine(session: AVAudioSession) {
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setPreferredSampleRate(48000.0)

            let outputFormat = inputNode.outputFormat(forBus: 0)
            sampleRate = outputFormat.sampleRate

            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: outputFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }

            audioEngine.prepare()

            try session.setActive(true)

            try audioEngine.start()

            isRecording = true
            resetState()

            #if DEBUG
            print("🎸 SimplifiedFFTTuner started - \(sampleRate)Hz")
            #endif

        } catch {
            #if DEBUG
            print("❌ Failed to start: \(error)")
            #endif
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        audioEngine.stop()
        inputNode.removeTap(onBus: 0)

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {}

        isRecording = false
        resetState()
    }

    private func resetState() {
        frequency = 0
        amplitude = 0
        currentNote = "--"
        cents = 0
        detectedString = nil
        confidence = 0
        frequencyHistory.removeAll()
        lastStableFrequency = 0
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData,
              let fftSetup = fftSetup else { return }

        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        // Calculate RMS
        let rms = calculateRMS(samples)

        // Simple noise gate
        guard rms > minRMS else {
            handleSilence()
            return
        }

        // Apply window function
        let windowed = applyHannWindow(samples)

        // Perform FFT
        let frequency = performFFT(windowed, fftSetup: fftSetup)

        // Validate and smooth
        let finalFrequency = validateAndSmooth(frequency)

        // Update UI
        updateUI(frequency: finalFrequency, amplitude: rms)
    }

    // MARK: - FFT Processing

    private func performFFT(_ buffer: [Float], fftSetup: FFTSetup) -> Float {
        // Prepare for FFT
        var realPart = buffer
        var imagPart = [Float](repeating: 0, count: buffer.count)

        var resultFrequency: Float = 0

        // Perform FFT
        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )

                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Calculate magnitude spectrum
                var magnitudes = [Float](repeating: 0, count: halfFFTSize)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfFFTSize))

                // Find peak in guitar range (70-400 Hz)
                let minBin = Int(70.0 * Float(fftSize) / Float(sampleRate))
                let maxBinLimit = min(Int(400.0 * Float(fftSize) / Float(sampleRate)), halfFFTSize - 1)

                var maxMagnitude: Float = 0
                var peakBin = 0

                for bin in minBin ... maxBinLimit {
                    if magnitudes[bin] > maxMagnitude {
                        maxMagnitude = magnitudes[bin]
                        peakBin = bin
                    }
                }

                // Parabolic interpolation for sub-bin accuracy
                if peakBin > 0 && peakBin < halfFFTSize - 1 {
                    let y1 = magnitudes[peakBin - 1]
                    let y2 = magnitudes[peakBin]
                    let y3 = magnitudes[peakBin + 1]

                    let x0 = (y3 - y1) / (2 * (2 * y2 - y1 - y3))

                    if abs(x0) < 1 {
                        let refinedBin = Float(peakBin) + x0
                        resultFrequency = refinedBin * Float(sampleRate) / Float(fftSize)
                    } else {
                        resultFrequency = Float(peakBin) * Float(sampleRate) / Float(fftSize)
                    }
                } else {
                    resultFrequency = Float(peakBin) * Float(sampleRate) / Float(fftSize)
                }
            }
        }

        return resultFrequency
    }

    // MARK: - Window Function

    private func applyHannWindow(_ samples: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: samples.count)
        let N = samples.count

        for i in 0 ..< N {
            let window = 0.5 * (1 - cos(2 * Float.pi * Float(i) / Float(N - 1)))
            result[i] = samples[i] * window
        }

        return result
    }

    // MARK: - Validation and Smoothing

    private func validateAndSmooth(_ frequency: Float) -> Float {
        // Check if frequency is in valid range
        guard frequency > 70 && frequency < 400 else {
            return lastStableFrequency
        }

        // Add to history
        frequencyHistory.append(frequency)
        if frequencyHistory.count > historyMaxSize {
            frequencyHistory.removeFirst()
        }

        // Need enough samples
        guard frequencyHistory.count >= 3 else {
            lastStableFrequency = frequency
            return frequency
        }

        // Simple median filter
        let sorted = frequencyHistory.sorted()
        let median = sorted[sorted.count / 2]

        // Check for octave errors
        if lastStableFrequency > 0 {
            let ratio = median / lastStableFrequency

            // Octave jump detection
            if (ratio > 1.9 && ratio < 2.1) || (ratio > 0.45 && ratio < 0.55) {
                // Likely octave error, keep previous
                return lastStableFrequency
            }

            // Large jump detection
            if abs(ratio - 1.0) > 0.2 {
                // Check if it's near a guitar string
                var isNearString = false
                for string in guitarStrings {
                    let cents = abs(1200 * log2(median / string.frequency))
                    if cents < 100 {
                        isNearString = true
                        break
                    }
                }

                if !isNearString {
                    return lastStableFrequency
                }
            }
        }

        // Exponential smoothing
        if lastStableFrequency == 0 {
            lastStableFrequency = median
        } else {
            lastStableFrequency = 0.7 * lastStableFrequency + 0.3 * median
        }

        return lastStableFrequency
    }

    // MARK: - Handle Silence

    private func handleSilence() {
        if !frequencyHistory.isEmpty {
            frequencyHistory.removeLast()
        }

        if frequencyHistory.isEmpty {
            updateUI(frequency: 0, amplitude: 0)
            lastStableFrequency = 0
        }
    }

    // MARK: - RMS Calculation

    private func calculateRMS(_ samples: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
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

    private func updateUI(frequency: Float, amplitude: Float) {
        DispatchQueue.main.async {
            self.frequency = frequency
            self.amplitude = amplitude

            if frequency > 0 {
                let noteData = self.frequencyToNote(frequency)
                self.currentNote = "\(noteData.note)\(noteData.octave)"
                self.cents = noteData.cents
                self.detectedString = self.detectGuitarString(frequency)
                self.confidence = min(1.0, amplitude * 20)

                #if DEBUG
                print("🎸 \(self.currentNote): \(String(format: "%.1f", frequency))Hz (\(self.cents > 0 ? "+" : "")\(self.cents)¢)")
                #endif
            } else {
                self.currentNote = "--"
                self.cents = 0
                self.detectedString = nil
                self.confidence = 0
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
