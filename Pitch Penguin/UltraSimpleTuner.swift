//
//  UltraSimpleTuner.swift
//  Pitch Penguin
//
//  극도로 단순화된 튜너 - 안정성 최우선
//

import SwiftUI
import AVFoundation
import Accelerate

final class UltraSimpleTuner: ObservableObject {
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
    private let fftSize = 4096  // Smaller for faster processing
    private var halfFFTSize: Int { fftSize / 2 }
    private var log2n: vDSP_Length { vDSP_Length(log2(Float(fftSize))) }
    
    // MARK: - Processing Settings
    private let minRMS: Float = 0.02  // Higher threshold for cleaner signal
    private let bufferSize: AVAudioFrameCount = 4096
    
    // MARK: - Ultra Heavy Smoothing
    private var displayedFrequency: Float = 0
    private var rawFrequencyBuffer: [Float] = []
    private let rawBufferSize = 30  // Very large buffer
    private var consecutiveGoodReadings = 0
    
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
        setupFFT()
    }
    
    deinit {
        if let fftSetup = fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }
    
    private func setupFFT() {
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }
    
    // MARK: - Recording Control
    func startRecording() {
        guard !isRecording else { return }

        let session = AVAudioSession.sharedInstance()
        
        switch session.recordPermission {
        case .granted:
            setupAndStartEngine(session: session)
        case .denied:
            print("❌ Microphone permission denied. Please enable it in Settings.")
            // Consider showing an alert to the user
            return
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupAndStartEngine(session: session)
                    } else {
                        print("❌ Microphone permission was not granted.")
                    }
                }
            }
        @unknown default:
            print("❌ Unknown case for record permission")
        }
    }

    private func setupAndStartEngine(session: AVAudioSession) {
        do {
            print("✅ Permission granted. Attempting to start engine with minimal setup...")
            
            // 1. Configure session
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            
            // 2. Prepare the engine
            audioEngine.prepare()
            
            // 3. Activate the session
            try session.setActive(true)
            
            // 4. Start the engine
            try audioEngine.start()
            
            // NOTE: Tap is NOT installed for this test.
            
            DispatchQueue.main.async {
                self.isRecording = true
                print("✅✅✅ Audio engine started successfully! The problem is likely in the tap installation or audio processing.")
            }
            
        } catch {
            print("❌❌❌ Failed to start even with minimal setup: \(error)")
            print("The problem is fundamental to the engine start or session activation.")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch { }
        
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
        displayedFrequency = 0
        rawFrequencyBuffer.removeAll()
        consecutiveGoodReadings = 0
    }
    
    // MARK: - Audio Processing
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData,
              let fftSetup = fftSetup else { return }
        
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        
        // Calculate RMS
        let rms = calculateRMS(samples)
        
        // Strong noise gate
        guard rms > minRMS else {
            handleSilence()
            return
        }
        
        // Simple window
        let windowed = applyWindow(samples)
        
        // FFT
        let rawFreq = performSimpleFFT(windowed, fftSetup: fftSetup)
        
        // Process frequency
        processFrequency(rawFreq, amplitude: rms)
    }
    
    // MARK: - Simple FFT
    private func performSimpleFFT(_ buffer: [Float], fftSetup: FFTSetup) -> Float {
        var realPart = buffer
        var imagPart = [Float](repeating: 0, count: buffer.count)
        
        var resultFreq: Float = 0
        
        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )
                
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                
                // Magnitude spectrum
                var magnitudes = [Float](repeating: 0, count: halfFFTSize)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfFFTSize))
                
                // Find peak in guitar range only
                let minBin = Int(70.0 * Float(fftSize) / Float(sampleRate))
                let maxBin = min(Int(350.0 * Float(fftSize) / Float(sampleRate)), halfFFTSize - 1)
                
                var maxMag: Float = 0
                var peakBin = 0
                
                for bin in minBin...maxBin {
                    if magnitudes[bin] > maxMag {
                        maxMag = magnitudes[bin]
                        peakBin = bin
                    }
                }
                
                // Simple frequency calculation
                resultFreq = Float(peakBin) * Float(sampleRate) / Float(fftSize)
            }
        }
        
        return resultFreq
    }
    
    // MARK: - Process Frequency
    private func processFrequency(_ rawFreq: Float, amplitude: Float) {
        // Validate range
        guard rawFreq > 70 && rawFreq < 350 else {
            handleSilence()
            return
        }
        
        // Add to buffer
        rawFrequencyBuffer.append(rawFreq)
        if rawFrequencyBuffer.count > rawBufferSize {
            rawFrequencyBuffer.removeFirst()
        }
        
        // Need enough samples
        guard rawFrequencyBuffer.count >= 10 else {
            return
        }
        
        // Remove outliers
        let sorted = rawFrequencyBuffer.sorted()
        let q1Index = sorted.count / 4
        let q3Index = (sorted.count * 3) / 4
        let q1 = sorted[q1Index]
        let q3 = sorted[q3Index]
        let iqr = q3 - q1
        
        let filtered = rawFrequencyBuffer.filter { freq in
            freq >= (q1 - 1.5 * iqr) && freq <= (q3 + 1.5 * iqr)
        }
        
        guard !filtered.isEmpty else {
            return
        }
        
        // Calculate median of filtered values
        let filteredSorted = filtered.sorted()
        let median = filteredSorted[filteredSorted.count / 2]
        
        // Check if stable
        let variance = filtered.map { pow($0 - median, 2) }.reduce(0, +) / Float(filtered.count)
        let isStable = variance < 4.0
        
        // Update displayed frequency with heavy smoothing
        if displayedFrequency == 0 {
            // First reading
            displayedFrequency = median
        } else {
            // Check for octave jumps
            let ratio = median / displayedFrequency
            if ratio > 1.8 && ratio < 2.2 {
                // Likely octave error, ignore
                return
            } else if ratio > 0.45 && ratio < 0.55 {
                // Likely octave error, ignore
                return
            }
            
            // Apply heavy smoothing
            let smoothingFactor: Float = isStable ? 0.85 : 0.7
            displayedFrequency = smoothingFactor * displayedFrequency + (1 - smoothingFactor) * median
        }
        
        // Count consecutive good readings
        if isStable {
            consecutiveGoodReadings += 1
        } else {
            consecutiveGoodReadings = 0
        }
        
        // Update UI
        updateUI(frequency: displayedFrequency, amplitude: amplitude, isStable: consecutiveGoodReadings > 5)
    }
    
    // MARK: - Window Function
    private func applyWindow(_ samples: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: samples.count)
        let N = samples.count
        
        for i in 0..<N {
            // Hann window
            let window = 0.5 * (1 - cos(2 * Float.pi * Float(i) / Float(N - 1)))
            result[i] = samples[i] * window
        }
        
        return result
    }
    
    // MARK: - Handle Silence
    private func handleSilence() {
        consecutiveGoodReadings = 0
        
        // Slowly fade out frequency
        if displayedFrequency > 0 {
            displayedFrequency *= 0.95
            if displayedFrequency < 10 {
                displayedFrequency = 0
                rawFrequencyBuffer.removeAll()
            }
        }
        
        if displayedFrequency == 0 {
            updateUI(frequency: 0, amplitude: 0, isStable: false)
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
    private func updateUI(frequency: Float, amplitude: Float, isStable: Bool) {
        DispatchQueue.main.async {
            self.frequency = frequency
            self.amplitude = amplitude
            self.confidence = isStable ? 1.0 : 0.3
            
            if frequency > 0 {
                let noteData = self.frequencyToNote(frequency)
                self.currentNote = "\(noteData.note)\(noteData.octave)"
                self.cents = noteData.cents
                self.detectedString = self.detectGuitarString(frequency)
                
                let icon = isStable ? "✅" : "🎸"
                print("\(icon) \(self.currentNote): \(String(format: "%.1f", frequency))Hz (\(self.cents > 0 ? "+" : "")\(self.cents)¢)")
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
        var minCents: Float = Float.greatestFiniteMagnitude
        
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