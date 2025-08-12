//
//  AudioEngine.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import AVFoundation
import Accelerate

class AudioEngine: NSObject, ObservableObject {
    @Published var detectedFrequency: Double = 0.0
    @Published var isRecording = false
    
    internal var audioEngine: AVAudioEngine!
    internal var inputNode: AVAudioInputNode!
    internal var bus: Int = 0
    
    private let bufferSize: UInt32 = 4096  // Larger buffer for better accuracy
    internal var sampleRate: Double = 44100.0
    
    // Pitch stabilization - minimal buffering for responsiveness
    private var frequencyBuffer: [Double] = []
    private let bufferMaxSize = 2  // Minimal buffering
    
    // Smooth frequency tracking
    private var smoothedFrequency: Double = 0.0
    private let smoothingFactor: Double = 0.3  // Light smoothing for responsiveness
    
    // Dynamic noise gate
    private var noiseGateThreshold: Float = 0.001 // Low threshold for sensitivity
    private var noiseFloor: Float = 0.0
    private var noiseBuffer: [Float] = []
    private let noiseBufferSize = 50
    private let noiseMultiplier: Float = 3.5 // Adaptive threshold multiplier
    
    // Advanced pitch detection
    internal var hybridDetector: HybridPitchDetector?
    private var lastConfidence: Float = 0.0
    
    // Performance optimization
    private var windowFunction: [Float] = []
    private let combFilter = CombFilter()
    
    // Multi-threading
    private let processingQueue = DispatchQueue(label: "com.pitchpenguin.dsp", qos: .userInteractive)
    private let processingSemaphore = DispatchSemaphore(value: 1)
    
    // Adaptive buffer
    private var adaptiveBufferSize: UInt32 = 1024
    private let lowFreqThreshold: Double = 150.0  // Below this, use larger buffer
    
    // MARK: - Low-latency pipeline
    private let processFrameCount = 2048
    private let hopSize = 512 // 75% overlap
    private var ring = [Float]()
    private var bpFilter = BPFilter()
    private var stabilizer = Stabilizer()
    private let levelMeter = LiveLevelMeter()
    
    // Noise calibration (adaptive gate)
    private var calibrated = false
    private var noiseMean: Float = 0
    private var noiseStd: Float = 0
    private var calibSamples: [Float] = []
    private let calibDurationFrames = 48_000 / 2 // 0.5s @ 48k
    
    // Smooth decay for no detection
    private var lastDetectedFrequency: Double = 0
    
    // Battery optimization
    private var silenceTimer: Timer?
    private var consecutiveSilentFrames = 0
    private let silenceThreshold = 50  // ~1 second of silence
    
    // Debug counter
    private var debugCounter = 0
    
    // Test mode
    private var testMode = false
    private var testTimer: Timer?
    
    override init() {
        super.init()
        setupAudio()
        setupWindowFunction()
    }
    
    private func setupAudio() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
    }
    
    private func setupWindowFunction() {
        // Use larger size to accommodate any buffer size
        windowFunction = [Float](repeating: 0, count: 4096)
        vDSP_hamm_window(&windowFunction, vDSP_Length(4096), 0)
        print("DEBUG: Window function initialized with size: \(windowFunction.count)")
    }
    
    func startRecording() {
        // Prevent duplicate starts
        if isRecording {
            return
        }
        
        do {
            // Use new realtime input system
            try startRealtimeInput()
            
            // Initialize hybrid detector with 48k sample rate
            sampleRate = 48_000
            hybridDetector = HybridPitchDetector(sampleRate: sampleRate)
            print("DEBUG: Hybrid detector initialized with sample rate: \(sampleRate)")
            
            print("DEBUG: Audio engine started successfully!")
            print("DEBUG: Is running: \(audioEngine.isRunning)")
            
            DispatchQueue.main.async {
                self.isRecording = true
                print("DEBUG: Recording started, isRecording = true")
                
                // Test mode disabled - use real audio
                // self.startTestMode()
            }
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        inputNode.removeTap(onBus: bus)
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        
        stopTestMode()
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.detectedFrequency = 0.0
            self.frequencyBuffer.removeAll()
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { 
            print("DEBUG: No channel data")
            return 
        }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Use all available frames for better accuracy
        let processFrameCount = frameCount
        
        // Debug counter
        debugCounter += 1
        if debugCounter % 20 == 0 {
            print("DEBUG: Processing buffer - received frames: \(frameCount), processing: \(processFrameCount), channels: \(channelCount)")
        }
        
        // Convert to mono if stereo
        var monoData: [Float]
        if channelCount > 1 {
            monoData = [Float](repeating: 0, count: processFrameCount)
            for i in 0..<processFrameCount {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channelData[channel][i]
                }
                monoData[i] = sum / Float(channelCount)
            }
        } else {
            monoData = Array(UnsafeBufferPointer(start: channelData[0], count: processFrameCount))
        }
        
        // Calculate signal power
        var signalPower: Float = 0
        vDSP_measqv(monoData, 1, &signalPower, vDSP_Length(processFrameCount))
        signalPower = sqrt(signalPower)
        
        // Debug signal power
        if debugCounter % 20 == 0 {
            print("DEBUG: Signal power: \(signalPower), threshold: \(noiseGateThreshold)")
        }
        
        // Simple noise gate with fixed threshold
        if signalPower < noiseGateThreshold {
            if debugCounter % 20 == 0 {
                print("DEBUG: Signal below threshold, skipping")
            }
            DispatchQueue.main.async {
                self.detectedFrequency = 0.0
            }
            return
        }
        
        // Force some movement for testing
        if signalPower > 0.0001 {
            print("DEBUG: Processing signal with power: \(signalPower)")
        }
        
        // Apply high-pass filter to remove low frequency noise
        let filteredData = applyHighPassFilter(channelData: monoData, frameCount: processFrameCount)
        
        // Apply window function
        let windowedData = applyWindow(data: filteredData, frameCount: processFrameCount)
        
        // Use YIN algorithm first for accuracy
        let yinFreq = detectPitch(channelData: windowedData, frameCount: processFrameCount)
        
        // Use hybrid detector for validation if available
        var finalFrequency = yinFreq
        if let hybrid = hybridDetector, yinFreq > 0 {
            finalFrequency = hybrid.detectPitch(data: windowedData, yinResult: yinFreq)
        }
        
        if debugCounter % 20 == 0 {
            print("DEBUG: YIN: \(yinFreq) Hz, Final: \(finalFrequency) Hz")
        }
        
        if finalFrequency > 0 {
            print("DEBUG: Frequency detected: \(finalFrequency) Hz")
            updateFrequency(finalFrequency)
        } else {
            // Try simple method as fallback
            let simpleFreq = detectPitchSimple(channelData: windowedData, frameCount: processFrameCount)
            if simpleFreq > 0 {
                print("DEBUG: Simple method detected: \(simpleFreq) Hz")
                updateFrequency(simpleFreq)
            } else {
                if debugCounter % 20 == 0 {
                    print("DEBUG: No frequency detected")
                }
                DispatchQueue.main.async {
                    self.detectedFrequency = 0.0
                    self.frequencyBuffer.removeAll()
                }
            }
        }
    }
    
    private func applyHighPassFilter(channelData: [Float], frameCount: Int) -> [Float] {
        var filtered = [Float](repeating: 0, count: frameCount)
        let cutoffFreq: Float = 80.0 // Hz
        let RC = 1.0 / (2.0 * Float.pi * cutoffFreq)
        let dt = 1.0 / Float(sampleRate)
        let alpha = RC / (RC + dt)
        
        filtered[0] = channelData[0]
        for i in 1..<frameCount {
            filtered[i] = alpha * (filtered[i-1] + channelData[i] - channelData[i-1])
        }
        
        return filtered
    }
    
    private func applyWindow(data: [Float], frameCount: Int) -> [Float] {
        var windowedData = [Float](repeating: 0, count: frameCount)
        var window = [Float](repeating: 0, count: frameCount)
        
        // Generate Hamming window
        vDSP_hamm_window(&window, vDSP_Length(frameCount), 0)
        
        // Apply window
        vDSP_vmul(data, 1, window, 1, &windowedData, 1, vDSP_Length(frameCount))
        
        return windowedData
    }
    
    private func updateFrequency(_ frequency: Double) {
        // Simple exponential moving average
        if smoothedFrequency > 0 {
            smoothedFrequency = smoothingFactor * frequency + (1 - smoothingFactor) * smoothedFrequency
        } else {
            smoothedFrequency = frequency
        }
        
        print("DEBUG: Updating UI with frequency: \(smoothedFrequency)")
        
        // Direct update for immediate response
        DispatchQueue.main.async {
            self.detectedFrequency = self.smoothedFrequency
            print("DEBUG: UI updated with: \(self.detectedFrequency)")
        }
    }
    
    private func stabilizeFrequency(_ frequency: Double) {
        // Kept for compatibility but simplified
        updateFrequency(frequency)
    }
    
    internal func detectPitch(channelData: [Float], frameCount: Int, minFreq: Double = 70.0, maxFreq: Double = 1200.0, threshold: Float = 0.12) -> Double {
        // Updated parameters for better range
        
        let minPeriod = Int(sampleRate / maxFreq)
        let maxPeriod = min(Int(sampleRate / minFreq), frameCount / 2)
        
        // Ensure we have enough data
        if frameCount < minPeriod * 2 {
            return 0.0
        }
        
        var yinBuffer = [Float](repeating: 0, count: maxPeriod)
        
        // Calculate autocorrelation with optimization
        for tau in 1..<maxPeriod {
            var sum: Float = 0
            let limit = min(frameCount - tau, frameCount / 2)
            
            // Simple difference calculation for reliability
            for i in 0..<limit {
                let diff = channelData[i] - channelData[i + tau]
                sum += diff * diff
            }
            
            yinBuffer[tau] = sum
        }
        
        // Cumulative mean normalized difference
        var runningSum: Float = 0
        yinBuffer[0] = 1
        
        for tau in 1..<maxPeriod {
            runningSum += yinBuffer[tau]
            if runningSum != 0 {
                yinBuffer[tau] *= Float(tau) / runningSum
            } else {
                yinBuffer[tau] = 1
            }
        }
        
        // Find the first minimum below threshold
        var tau = minPeriod
        while tau < maxPeriod - 1 {
            if yinBuffer[tau] < threshold {
                // Refine to find the true minimum
                while tau + 1 < maxPeriod && yinBuffer[tau + 1] < yinBuffer[tau] {
                    tau += 1
                }
                break
            }
            tau += 1
        }
        
        if tau == maxPeriod - 1 || yinBuffer[tau] >= threshold {
            return 0.0
        }
        
        // Parabolic interpolation for sub-sample accuracy
        var betterTau: Float
        if tau > 0 && tau < maxPeriod - 1 {
            let s0 = yinBuffer[tau - 1]
            let s1 = yinBuffer[tau]
            let s2 = yinBuffer[tau + 1]
            
            let a = s2 - 2.0 * s1 + s0
            
            if a != 0 {
                betterTau = Float(tau) + (s0 - s2) / (2.0 * a)
            } else {
                betterTau = Float(tau)
            }
        } else {
            betterTau = Float(tau)
        }
        
        let frequency = sampleRate / Double(betterTau)
        
        // Validate frequency is within expected range
        if frequency >= minFreq && frequency <= maxFreq {
            return frequency
        }
        
        return 0.0
    }
    
    private func detectPitchSimple(channelData: [Float], frameCount: Int) -> Double {
        let minFreq: Double = 60.0
        let maxFreq: Double = 800.0
        
        let minPeriod = Int(sampleRate / maxFreq)
        let maxPeriod = min(Int(sampleRate / minFreq), frameCount - 1)
        
        if frameCount < minPeriod * 2 {
            return 0.0
        }
        
        // Find maximum autocorrelation
        var maxCorrelation: Float = 0
        var bestPeriod = 0
        
        for period in minPeriod..<maxPeriod {
            var correlation: Float = 0
            let count = frameCount - period
            
            for i in 0..<count {
                correlation += channelData[i] * channelData[i + period]
            }
            
            correlation = correlation / Float(count)
            
            if correlation > maxCorrelation {
                maxCorrelation = correlation
                bestPeriod = period
            }
        }
        
        if bestPeriod > 0 && maxCorrelation > 0.001 {  // 더 낮은 임계값
            return sampleRate / Double(bestPeriod)
        }
        
        return 0.0
    }
    
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        }
    }
    
    // MARK: - Dynamic Noise Floor
    
    private func updateNoiseFloor(signalPower: Float) {
        // Add to noise buffer
        noiseBuffer.append(signalPower)
        
        // Keep buffer size limited
        if noiseBuffer.count > noiseBufferSize {
            noiseBuffer.removeFirst()
        }
        
        // Calculate noise floor as the 10th percentile of recent samples
        if noiseBuffer.count >= 10 {
            let sorted = noiseBuffer.sorted()
            let index = Int(Float(sorted.count) * 0.1) // 10th percentile
            noiseFloor = sorted[index]
        }
    }
    
    // MARK: - Enhanced Harmonic Analysis
    
    private func calculateHarmonicConfidence(frequency: Double, data: [Float]) -> Float {
        guard frequency > 0 else { return 0.0 }
        
        // Ensure power of 2 size
        let nextPowerOf2 = 1 << Int(ceil(log2(Double(data.count))))
        var paddedData = [Float](repeating: 0, count: nextPowerOf2)
        paddedData.replaceSubrange(0..<data.count, with: data)
        
        // Prepare for FFT
        let log2n = vDSP_Length(log2(Float(paddedData.count)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2)) else { return 0.0 }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        var realp = [Float](repeating: 0, count: paddedData.count/2)
        var imagp = [Float](repeating: 0, count: paddedData.count/2)
        var magnitudes = [Float](repeating: 0, count: paddedData.count/2)
        
        // Apply window if available
        var windowedData = paddedData
        if windowFunction.count >= paddedData.count {
            vDSP_vmul(paddedData, 1, windowFunction, 1, &windowedData, 1, vDSP_Length(paddedData.count))
        }
        
        // Convert to split complex format and perform FFT
        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                
                // Pack real data into complex format
                windowedData.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: paddedData.count/2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(paddedData.count/2))
                    }
                }
                
                // Perform FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, Int32(FFT_FORWARD))
                
                // Calculate magnitude spectrum
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(paddedData.count/2))
            }
        }
        
        // Calculate harmonic score
        var harmonicScore: Float = 0.0
        let freqFloat = Float(frequency)
        let sampleRateFloat = Float(sampleRate)
        let binSize = sampleRateFloat / Float(paddedData.count)
        let fundamentalBin = Int(freqFloat / binSize)
        
        // Check first 5 harmonics
        for harmonic in 1...5 {
            let bin = fundamentalBin * harmonic
            if bin < magnitudes.count {
                // Get peak magnitude around expected harmonic
                let startBin = max(0, bin - 2)
                let endBin = min(magnitudes.count - 1, bin + 2)
                
                var maxMag: Float = 0
                for i in startBin...endBin {
                    if magnitudes[i] > maxMag {
                        maxMag = magnitudes[i]
                    }
                }
                
                // Weight higher harmonics less
                harmonicScore += maxMag / Float(harmonic)
            }
        }
        
        // Normalize confidence score
        return min(1.0, harmonicScore / 1000.0)
    }
    
    // MARK: - Adaptive Buffer Management (Disabled - using fixed tap)
    
    private func updateAdaptiveBufferSize(frequency: Double) {
        // Disabled - tap size is now fixed at 1024 for low latency
        // Adaptation happens internally via hopSize/processFrameCount
    }
    
    // MARK: - Battery Optimization
    
    private func enterLowPowerMode() {
        // Reduce processing when no sound detected for 1+ seconds
        DispatchQueue.main.async { [weak self] in
            self?.silenceTimer?.invalidate()
            self?.silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                // Minimal processing during silence
            }
        }
    }
    
    private func exitLowPowerMode() {
        DispatchQueue.main.async { [weak self] in
            self?.silenceTimer?.invalidate()
            self?.silenceTimer = nil
        }
    }
    
    // MARK: - Test Mode
    
    private func startTestMode() {
        testMode = true
        var testFrequencies: [Double] = [82.41, 110.0, 146.83, 196.0, 246.94, 329.63] // E A D G B E
        var currentIndex = 0
        
        testTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Simulate frequency detection
            let baseFreq = testFrequencies[currentIndex]
            let variation = Double.random(in: -5...5) // Simulate slight variations
            let testFreq = baseFreq + variation
            
            print("DEBUG TEST MODE: Simulating frequency: \(testFreq) Hz")
            
            DispatchQueue.main.async {
                self.detectedFrequency = testFreq
            }
            
            currentIndex = (currentIndex + 1) % testFrequencies.count
        }
    }
    
    private func stopTestMode() {
        testMode = false
        testTimer?.invalidate()
        testTimer = nil
    }
    
    // MARK: - Ring Buffer Processing
    
    // Tap 콜백이 호출하는 진입점: 링버퍼에 쌓고 2048/75% overlap로 처리
    func ingest(buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { 
            print("DEBUG: No channel data in buffer")
            return 
        }
        let n = Int(buffer.frameLength)
        ring.append(contentsOf: UnsafeBufferPointer(start: ch, count: n))

        // 초기 0.5초 환경 노이즈 캘리브레이션
        if !calibrated {
            calibSamples.append(contentsOf: UnsafeBufferPointer(start: ch, count: n))
            if calibSamples.count >= calibDurationFrames {
                var mean: Float = 0, std: Float = 0
                vDSP_normalize(calibSamples, 1, nil, 1, &mean, &std, vDSP_Length(calibSamples.count))
                noiseMean = mean
                noiseStd = max(std, 1e-7)
                calibrated = true
                calibSamples.removeAll(keepingCapacity: false)
                print("Noise calibrated: μ=\(noiseMean), σ=\(noiseStd)")
            }
            return // Don't process during calibration
        }

        while ring.count >= processFrameCount {
            let frame = Array(ring.prefix(processFrameCount))
            processFrame(frame)
            ring.removeFirst(hopSize)
        }
    }

    // 1 프레임(2048 샘플) 처리: 게이트 → 밴드패스 → 윈도우 → YIN/MPM → 안정화
    private func processFrame(_ monoData: [Float]) {
        // Check signal level
        var rms: Float = 0
        vDSP_rmsqv(monoData, 1, &rms, vDSP_Length(monoData.count))
        
        // Very low threshold for testing
        if rms < 0.00001 {
            print("DEBUG: Signal too quiet: \(rms)")
            DispatchQueue.main.async { self.detectedFrequency = 0 }
            return
        }
        
        print("DEBUG: RMS level: \(rms)")

        // Skip band-pass filter for now - use original data
        // let bandpassed = bpFilter.apply(monoData)
        let bandpassed = monoData

        // Hann window
        var window = [Float](repeating: 0, count: bandpassed.count)
        vDSP_hann_window(&window, vDSP_Length(bandpassed.count), Int32(vDSP_HANN_NORM))
        var windowed = [Float](repeating: 0, count: bandpassed.count)
        vDSP_vmul(bandpassed, 1, window, 1, &windowed, 1, vDSP_Length(bandpassed.count))

        // YIN 파라미터 통일 (70–1200 Hz, threshold 0.12)
        let yinHz = detectPitch(channelData: windowed,
                                frameCount: processFrameCount,
                                minFreq: 70.0,
                                maxFreq: 1200.0,
                                threshold: 0.12)
        
        print("DEBUG: YIN detected: \(yinHz) Hz")

        var finalHz = yinHz
        if let hybrid = hybridDetector, yinHz > 0 {
            finalHz = hybrid.detectPitch(data: windowed, yinResult: yinHz)
            print("DEBUG: Hybrid refined to: \(finalHz) Hz")
        }

        // Update level meter even if no pitch detected
        levelMeter.update(from: bandpassed)
        
        let medHz = stabilizer.push(finalHz)
        
        if medHz > 0 {
            lastDetectedFrequency = medHz
            DispatchQueue.main.async { self.detectedFrequency = medHz }
        } else {
            // Smooth decay instead of immediate 0
            lastDetectedFrequency *= 0.9
            if lastDetectedFrequency < 20 {
                lastDetectedFrequency = 0
            }
            DispatchQueue.main.async { self.detectedFrequency = self.lastDetectedFrequency }
        }
    }
}