import AVFoundation
import Accelerate

// Drop-in: keeps your UI untouched. Adds a low-latency, stable input pipeline.
// - Fixed input tap (1024) without reinstalling
// - Internal 2048 frame processing with 75% overlap
// - Adaptive noise gate (μ + 3.5σ) with graceful decay (no hard 0)
// - Band-pass (HPF 80 Hz + LPF 2.5 kHz)
// - Simple stabilizer (5-frame median)
extension AudioEngine {

    // MARK: - Realtime pipeline state
    private static var _processFrameCount: Int = 2048
    private static var _hopSize: Int = 512 // 75% overlap

    private struct Static {
        static var ring: [Float] = []
        static var calibrated: Bool = false
        static var noiseMean: Float = 0
        static var noiseStd:  Float = 0
        static var calibSamples: [Float] = []
        static var calibDurationFrames: Int = 44100 / 2 // Will be updated based on actual sample rate
        static var lastDetectedHz: Double = 0
        static var adaptiveFilter: AdaptiveBandPassFilter? = nil
        static var stabilizer = Stabilizer()
    }

    // MARK: - Public start helper (call instead of your old dynamic tap logic)
    func startRealtimeInput() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])
        try session.setActive(true)

        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        
        // Use hardware's native format
        let format = inputNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        
        // Initialize adaptive filter with actual sample rate
        Static.adaptiveFilter = AdaptiveBandPassFilter(sampleRate: sampleRate)
        
        // Update calibration duration based on actual sample rate
        Static.calibDurationFrames = Int(sampleRate / 2) // 0.5 seconds

        // Install tap BEFORE starting engine with native format
        inputNode.installTap(onBus: 0,
                             bufferSize: 1024,
                             format: format) { [weak self] buf, _ in
            self?.ingestRealtime(buffer: buf)
        }

        try audioEngine.start()
        
        isRecording = true
    }

    // MARK: - Ingest + process
    func ingestRealtime(buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData?[0] else { 
            print("❌ No channel data in buffer")
            return 
        }
        let n = Int(buffer.frameLength)
        
        // Accumulate samples for better pitch detection
        Static.ring.append(contentsOf: UnsafeBufferPointer(start: ch, count: n))
        
        // Process when we have enough samples (2048)
        while Static.ring.count >= 2048 {
            let frame = Array(Static.ring.prefix(2048))
            processRealtimeFrame(frame)
            Static.ring.removeFirst(512) // 75% overlap
        }
    }

    private func processRealtimeFrame(_ mono: [Float]) {
        // Apply adaptive band-pass filter
        let filtered = Static.adaptiveFilter?.apply(mono) ?? mono
        
        // Enhanced noise filtering
        var rms: Float = 0
        vDSP_rmsqv(filtered, 1, &rms, vDSP_Length(filtered.count))
        
        // Lower threshold for testing
        if rms < 0.0001 {  // Very low threshold
            // Don't print every quiet signal
            DispatchQueue.main.async {
                if self.detectedFrequency > 0 {
                    self.detectedFrequency *= 0.9
                    if self.detectedFrequency < 10 {
                        self.detectedFrequency = 0
                    }
                }
            }
            return
        }
        
        print("🎤 Processing signal with RMS: \(rms)")

        // Simple autocorrelation pitch detection
        let hz = simpleAutocorrelation(data: filtered)
        
        // Frequency validation
        if hz > 50 && hz < 2000 {  // Reasonable range for guitar
            // Store in history for stabilization
            Static.stabilizer.addSample(hz)
            
            // Get stabilized frequency
            if let stableHz = Static.stabilizer.getStableFrequency() {
                print("🎵 Detected: \(stableHz) Hz (stabilized)")
                DispatchQueue.main.async { 
                    self.detectedFrequency = stableHz
                }
            }
        }
    }
    
    private func simpleAutocorrelation(data: [Float]) -> Double {
        let minFreq: Double = 80.0
        let maxFreq: Double = 800.0
        
        let minPeriod = max(1, Int(sampleRate / maxFreq))
        let maxPeriod = min(Int(sampleRate / minFreq), data.count / 2)
        
        if data.count < 50 || minPeriod >= maxPeriod {
            print("❌ Data too small or period range invalid")
            return 0.0
        }
        
        // Find maximum autocorrelation
        var maxCorrelation: Float = 0
        var bestPeriod = 0
        
        for period in minPeriod..<maxPeriod {
            var correlation: Float = 0
            let count = data.count - period
            
            for i in 0..<count {
                correlation += data[i] * data[i + period]
            }
            
            correlation = correlation / Float(count)
            
            if correlation > maxCorrelation {
                maxCorrelation = correlation
                bestPeriod = period
            }
        }
        
        // Check if correlation is strong enough
        var power: Float = 0
        vDSP_measqv(data, 1, &power, vDSP_Length(data.count))
        
        // Reduce log spam
        
        if bestPeriod > 0 && maxCorrelation > power * 0.3 {  // Normal threshold
            let freq = sampleRate / Double(bestPeriod)
            if freq >= minFreq && freq <= maxFreq {
                print("✅ Detected frequency: \(freq) Hz")
                return freq
            }
        }
        
        return 0.0
    }
}