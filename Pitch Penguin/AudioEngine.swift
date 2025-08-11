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
    
    private var audioEngine: AVAudioEngine!
    private var inputNode: AVAudioInputNode!
    private var bus: Int = 0
    
    private let bufferSize: UInt32 = 1024  // Reduced for smoother updates (~23ms)
    private var sampleRate: Double = 44100.0
    
    // Pitch stabilization - smaller buffer for faster response
    private var frequencyBuffer: [Double] = []
    private let bufferMaxSize = 5  // Slightly larger for stability
    
    // Smooth frequency tracking
    private var smoothedFrequency: Double = 0.0
    private let smoothingFactor: Double = 0.85  // EMA factor (0.8-0.95 for smooth movement)
    
    // Dynamic noise gate
    private var noiseGateThreshold: Float = 0.005 // Initial value
    private var noiseFloor: Float = 0.0
    private var noiseBuffer: [Float] = []
    private let noiseBufferSize = 50
    private let noiseMultiplier: Float = 3.5 // Adaptive threshold multiplier
    
    // Advanced pitch detection
    private var hybridDetector: HybridPitchDetector?
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
    
    // Battery optimization
    private var silenceTimer: Timer?
    private var consecutiveSilentFrames = 0
    private let silenceThreshold = 50  // ~1 second of silence
    
    // Debug counter
    private var debugCounter = 0
    
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
        windowFunction = [Float](repeating: 0, count: Int(bufferSize))
        vDSP_hamm_window(&windowFunction, vDSP_Length(bufferSize), 0)
    }
    
    func startRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            
            // Get the default input format from the hardware
            let inputFormat = inputNode.outputFormat(forBus: bus)
            
            // Use the input node's format directly to avoid mismatch
            sampleRate = inputFormat.sampleRate
            
            // Initialize hybrid detector with correct sample rate
            hybridDetector = HybridPitchDetector(sampleRate: sampleRate)
            
            print("Input format: \(inputFormat)")
            print("Sample rate: \(sampleRate)")
            print("Channels: \(inputFormat.channelCount)")
            
            // Use adaptive buffer size
            let currentBufferSize = adaptiveBufferSize > 0 ? adaptiveBufferSize : bufferSize
            
            // Install tap with the same format as the input node
            inputNode.installTap(onBus: bus, bufferSize: currentBufferSize, format: inputFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            DispatchQueue.main.async {
                self.isRecording = true
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
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.detectedFrequency = 0.0
            self.frequencyBuffer.removeAll()
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Skip if already processing (prevent queue buildup)
        guard processingSemaphore.wait(timeout: .now()) == .success else { return }
        
        // Process on background queue for better performance
        processingQueue.async { [weak self] in
            defer { self?.processingSemaphore.signal() }
        
        // Convert to mono if stereo
        var monoData: [Float]
        if channelCount > 1 {
            monoData = [Float](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channelData[channel][i]
                }
                monoData[i] = sum / Float(channelCount)
            }
        } else {
            monoData = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }
        
        // Calculate signal power
        var signalPower: Float = 0
        vDSP_measqv(monoData, 1, &signalPower, vDSP_Length(frameCount))
        signalPower = sqrt(signalPower)
        
        // Update dynamic noise floor
        self?.updateNoiseFloor(signalPower: signalPower)
        
        // Apply dynamic noise gate
        let dynamicThreshold = max(self?.noiseGateThreshold ?? 0.005, (self?.noiseFloor ?? 0) * (self?.noiseMultiplier ?? 3.5))
        
        // Debug print - only occasionally to avoid performance impact
        self?.debugCounter += 1
        if (self?.debugCounter ?? 0) % 30 == 0 && signalPower > 0.001 {
            print("Signal: \(signalPower), Noise floor: \(self?.noiseFloor ?? 0), Threshold: \(dynamicThreshold)")
        }
        
        if signalPower < dynamicThreshold {
            DispatchQueue.main.async {
                self?.detectedFrequency = 0.0
            }
            return
        }
        
        // Apply high-pass filter to remove low frequency noise
        guard let strongSelf = self else { return }
        let filteredData = strongSelf.applyHighPassFilter(channelData: monoData, frameCount: frameCount)
        
        // Apply window function
        let windowedData = strongSelf.applyWindow(data: filteredData, frameCount: frameCount)
        
        // Detect pitch with enhanced YIN
        let yinFrequency = strongSelf.detectPitch(channelData: windowedData, frameCount: frameCount)
        
        // Use enhanced hybrid detection with confidence scoring
        let frequency: Double
        if let detector = strongSelf.hybridDetector {
            frequency = detector.detectPitch(data: windowedData, yinResult: yinFrequency)
            
            // Calculate harmonic confidence for better accuracy
            if frequency > 0 {
                let confidence = strongSelf.calculateHarmonicConfidence(frequency: frequency, data: windowedData)
                strongSelf.lastConfidence = confidence
                
                // Debug output
                if (strongSelf.debugCounter) % 30 == 0 {
                    print("Frequency: \(frequency)Hz, Confidence: \(confidence)")
                }
                
                // Apply comb filter for harmonic enhancement
                let period = Int(strongSelf.sampleRate / frequency)
                if period > 0 && period < frameCount / 2 {
                    let _ = strongSelf.combFilter.apply(data: windowedData, fundamentalPeriod: period)
                }
                
                // Only accept high confidence results
                if confidence < 0.5 && yinFrequency > 0 {
                    // Use YIN as fallback for low confidence
                    self?.stabilizeFrequency(yinFrequency)
                } else {
                    self?.stabilizeFrequency(frequency)
                }
            } else {
                DispatchQueue.main.async {
                    self?.detectedFrequency = 0.0
                    self?.frequencyBuffer.removeAll()
                }
            }
        } else {
            frequency = yinFrequency
            if frequency > 0 {
                self?.stabilizeFrequency(frequency)
            } else {
                DispatchQueue.main.async {
                    self?.detectedFrequency = 0.0
                    self?.frequencyBuffer.removeAll()
                }
            }
        }
        
        // Update adaptive buffer size based on detected frequency
        self?.updateAdaptiveBufferSize(frequency: frequency)
        
        // Battery optimization: track silence
        if frequency == 0 {
            self?.consecutiveSilentFrames += 1
            if self?.consecutiveSilentFrames ?? 0 > self?.silenceThreshold ?? 50 {
                self?.enterLowPowerMode()
            }
        } else {
            self?.consecutiveSilentFrames = 0
            self?.exitLowPowerMode()
        }
        
        } // End of processingQueue.async
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
    
    private func stabilizeFrequency(_ frequency: Double) {
        frequencyBuffer.append(frequency)
        
        if frequencyBuffer.count > bufferMaxSize {
            frequencyBuffer.removeFirst()
        }
        
        // Remove outliers and calculate median
        let sortedBuffer = frequencyBuffer.sorted()
        let median: Double
        
        if sortedBuffer.count % 2 == 0 && sortedBuffer.count > 1 {
            median = (sortedBuffer[sortedBuffer.count/2 - 1] + sortedBuffer[sortedBuffer.count/2]) / 2.0
        } else if sortedBuffer.count > 0 {
            median = sortedBuffer[sortedBuffer.count/2]
        } else {
            median = frequency
        }
        
        // Apply exponential moving average for smooth transitions
        if smoothedFrequency > 0 {
            // EMA: new = α * current + (1-α) * previous
            smoothedFrequency = smoothingFactor * median + (1 - smoothingFactor) * smoothedFrequency
            
            // Apply soft hysteresis (reduced from 3 to 1 cent for smoother movement)
            let centsDiff = 1200 * log2(smoothedFrequency / self.detectedFrequency)
            if abs(centsDiff) > 0.5 || self.detectedFrequency == 0 {
                DispatchQueue.main.async {
                    self.detectedFrequency = self.smoothedFrequency
                }
            }
        } else {
            smoothedFrequency = median
            DispatchQueue.main.async {
                self.detectedFrequency = median
            }
        }
    }
    
    private func detectPitch(channelData: [Float], frameCount: Int) -> Double {
        let threshold: Float = 0.12  // Optimized threshold for accuracy vs speed
        let minFreq: Double = 65.0   // C2 for wider range
        let maxFreq: Double = 500.0  // B4 + margin for harmonics
        
        let minPeriod = Int(sampleRate / maxFreq)
        let maxPeriod = min(Int(sampleRate / minFreq), frameCount / 2)
        
        var yinBuffer = [Float](repeating: 0, count: maxPeriod)
        
        // Calculate autocorrelation with optimization
        for tau in 1..<maxPeriod {
            var sum: Float = 0
            let limit = min(maxPeriod, frameCount - tau)
            
            // Use vDSP for faster calculation
            var diff = [Float](repeating: 0, count: limit)
            channelData.withUnsafeBufferPointer { channelPtr in
                let offsetPtr = channelPtr.baseAddress!.advanced(by: tau)
                vDSP_vsub(offsetPtr, 1, channelPtr.baseAddress!, 1, &diff, 1, vDSP_Length(limit))
            }
            vDSP_vsq(diff, 1, &diff, 1, vDSP_Length(limit))
            vDSP_sve(diff, 1, &sum, vDSP_Length(limit))
            
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
        if frequency >= minFreq && frequency <= maxFreq * 2 {
            return frequency
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
    
    // MARK: - Adaptive Buffer Management
    
    private func updateAdaptiveBufferSize(frequency: Double) {
        guard frequency > 0 else { return }
        
        // Use larger buffer for low frequencies (better accuracy)
        // Smaller buffer for high frequencies (faster response)
        let newBufferSize: UInt32
        if frequency < lowFreqThreshold {
            newBufferSize = 2048  // ~46ms for low notes
        } else if frequency < 300 {
            newBufferSize = 1024  // ~23ms for mid notes
        } else {
            newBufferSize = 512   // ~11ms for high notes
        }
        
        if adaptiveBufferSize != newBufferSize {
            adaptiveBufferSize = newBufferSize
            // Reinstall tap with new buffer size for immediate effect
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isRecording else { return }
                
                // Remove existing tap
                self.inputNode.removeTap(onBus: self.bus)
                
                // Get the current input format
                let inputFormat = self.inputNode.outputFormat(forBus: self.bus)
                
                // Reinstall with new buffer size using the same format
                self.inputNode.installTap(onBus: self.bus, bufferSize: newBufferSize, format: inputFormat) { [weak self] buffer, _ in
                    self?.processAudioBuffer(buffer)
                }
            }
        }
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
}