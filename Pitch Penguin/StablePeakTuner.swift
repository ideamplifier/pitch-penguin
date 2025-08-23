//
//  StablePeakTuner.swift
//  Pitch Penguin
//
//  Stable peak-based tuner with harmonic analysis
//

import Accelerate
import AVFoundation
import SwiftUI

final class StablePeakTuner: ObservableObject {
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
    private let fftSize = 16384 // Larger for better frequency resolution
    private var halfFFTSize: Int { fftSize / 2 }
    private var log2n: vDSP_Length { vDSP_Length(log2(Float(fftSize))) }

    // MARK: - Processing Settings

    private let minRMS: Float = 0.015 // Slightly higher threshold
    private let bufferSize: AVAudioFrameCount = 16384

    // MARK: - Stability Buffer

    private var recentFrequencies: [Float] = []
    private let bufferMaxSize = 20
    private var lockedFrequency: Float = 0
    private var lockCounter = 0

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
            #if DEBUG
            print("❌ Microphone permission denied. Please enable it in Settings.")
            #endif
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
                        #if DEBUG
                        print("❌ Microphone permission was not granted.")
                        #endif
                        #endif
                    }
                }
            }
        @unknown default:
            #if DEBUG
            #if DEBUG
            print("❌ Unknown case for record permission")
            #endif
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
            #if DEBUG
            print("🎸 StablePeakTuner started - \(sampleRate)Hz")
            #endif
            #endif

        } catch {
            #if DEBUG
            #if DEBUG
            print("❌ Failed to start: \(error)")
            #endif
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
        recentFrequencies.removeAll()
        lockedFrequency = 0
        lockCounter = 0
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData,
              let fftSetup = fftSetup else { return }

        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        // Calculate RMS
        let rms = calculateRMS(samples)

        // Higher noise gate for stability
        guard rms > minRMS else {
            handleSilence()
            return
        }

        // Apply window
        let windowed = applyBlackmanWindow(samples)

        // FFT Analysis
        let spectrum = performFFT(windowed, fftSetup: fftSetup)

        // Find fundamental frequency
        let detectedFreq = findFundamentalFrequency(spectrum)

        // Apply stability filter
        let stableFreq = stabilityFilter(detectedFreq)

        // Update UI
        updateUI(frequency: stableFreq, amplitude: rms)
    }

    // MARK: - FFT Processing

    private func performFFT(_ buffer: [Float], fftSetup: FFTSetup) -> [Float] {
        var realPart = buffer
        var imagPart = [Float](repeating: 0, count: buffer.count)
        var magnitudes = [Float](repeating: 0, count: halfFFTSize)

        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )

                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfFFTSize))
            }
        }

        // Convert to dB and normalize
        var logMagnitudes = [Float](repeating: 0, count: halfFFTSize)
        var one: Float = 1.0
        vDSP_vdbcon(magnitudes, 1, &one, &logMagnitudes, 1, vDSP_Length(halfFFTSize), 0)

        return logMagnitudes
    }

    // MARK: - Find Fundamental Frequency

    private func findFundamentalFrequency(_ spectrum: [Float]) -> Float {
        // Define search range for guitar (65-400 Hz)
        let minBin = Int(65.0 * Float(fftSize) / Float(sampleRate))
        let maxBin = min(Int(400.0 * Float(fftSize) / Float(sampleRate)), halfFFTSize - 1)

        // Find peaks in spectrum
        var peaks: [(bin: Int, magnitude: Float)] = []

        for bin in (minBin + 1) ..< (maxBin - 1) {
            // Local maximum detection
            if spectrum[bin] > spectrum[bin - 1] &&
                spectrum[bin] > spectrum[bin + 1] &&
                spectrum[bin] > -40
            { // Threshold in dB
                peaks.append((bin: bin, magnitude: spectrum[bin]))
            }
        }

        // Sort peaks by magnitude
        peaks.sort { $0.magnitude > $1.magnitude }

        // Take top peaks
        let topPeaks = Array(peaks.prefix(10))

        // Find the lowest frequency among strong peaks (likely fundamental)
        var lowestStrongPeak: Int? = nil
        let threshold = (topPeaks.first?.magnitude ?? -100) - 12 // 12dB below strongest

        for peak in topPeaks {
            if peak.magnitude > threshold {
                if lowestStrongPeak == nil || peak.bin < lowestStrongPeak! {
                    lowestStrongPeak = peak.bin
                }
            }
        }

        guard let fundamentalBin = lowestStrongPeak else { return 0 }

        // Parabolic interpolation
        if fundamentalBin > 0 && fundamentalBin < halfFFTSize - 1 {
            let y1 = spectrum[fundamentalBin - 1]
            let y2 = spectrum[fundamentalBin]
            let y3 = spectrum[fundamentalBin + 1]

            let x0 = (y3 - y1) / (2 * (2 * y2 - y1 - y3))

            if abs(x0) < 1 {
                let refinedBin = Float(fundamentalBin) + x0
                return refinedBin * Float(sampleRate) / Float(fftSize)
            }
        }

        return Float(fundamentalBin) * Float(sampleRate) / Float(fftSize)
    }

    // MARK: - Stability Filter

    private func stabilityFilter(_ frequency: Float) -> Float {
        // Check valid range
        guard frequency > 65 && frequency < 400 else {
            lockCounter = max(0, lockCounter - 1)
            if lockCounter == 0 {
                lockedFrequency = 0
            }
            return lockedFrequency
        }

        // Add to buffer
        recentFrequencies.append(frequency)
        if recentFrequencies.count > bufferMaxSize {
            recentFrequencies.removeFirst()
        }

        // Need minimum samples
        guard recentFrequencies.count >= 5 else {
            return frequency
        }

        // Calculate statistics
        let sortedFreqs = recentFrequencies.sorted()
        let median = sortedFreqs[sortedFreqs.count / 2]
        let mean = recentFrequencies.reduce(0, +) / Float(recentFrequencies.count)

        // Calculate variance
        let variance = recentFrequencies.map { pow($0 - mean, 2) }.reduce(0, +) / Float(recentFrequencies.count)
        let stdDev = sqrt(variance)

        // If very stable, lock the frequency
        if stdDev < 2.0 {
            lockedFrequency = median
            lockCounter = 10
            return lockedFrequency
        }

        // If locked, maintain lock if new frequency is close
        if lockCounter > 0 {
            let cents = abs(1200 * log2(frequency / lockedFrequency))
            if cents < 50 { // Within 50 cents
                lockCounter = 10 // Reset counter
                // Slowly adjust locked frequency
                lockedFrequency = 0.9 * lockedFrequency + 0.1 * frequency
            } else {
                lockCounter -= 1
            }
            return lockedFrequency
        }

        // Otherwise return median
        return median
    }

    // MARK: - Window Function

    private func applyBlackmanWindow(_ samples: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: samples.count)
        let N = Float(samples.count - 1)

        for i in 0 ..< samples.count {
            let n = Float(i)
            let window = 0.42 - 0.5 * cos(2 * Float.pi * n / N) + 0.08 * cos(4 * Float.pi * n / N)
            result[i] = samples[i] * window
        }

        return result
    }

    // MARK: - Handle Silence

    private func handleSilence() {
        lockCounter = max(0, lockCounter - 1)

        if lockCounter == 0 {
            recentFrequencies.removeAll()
            lockedFrequency = 0
            updateUI(frequency: 0, amplitude: 0)
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
                self.confidence = self.lockCounter > 0 ? 1.0 : 0.5

                if self.lockCounter > 0 {
                    #if DEBUG
                    #if DEBUG
                    print("🔒 LOCKED: \(self.currentNote) \(String(format: "%.1f", frequency))Hz (\(self.cents > 0 ? "+" : "")\(self.cents)¢)")
                    #endif
                    #endif
                } else {
                    #if DEBUG
                    #if DEBUG
                    print("🎸 \(self.currentNote): \(String(format: "%.1f", frequency))Hz (\(self.cents > 0 ? "+" : "")\(self.cents)¢)")
                    #endif
                    #endif
                }
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
