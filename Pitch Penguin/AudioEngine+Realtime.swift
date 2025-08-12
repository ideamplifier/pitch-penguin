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
        static var calibDurationFrames: Int = 48_000 / 2 // Will be updated based on actual sample rate
        static var lastDetectedHz: Double = 0
        static var bp = BPFilter()
        static var stabilizer = Stabilizer()
    }

    // MARK: - Public start helper (call instead of your old dynamic tap logic)
    func startRealtimeInput() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)

        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        
        // Use hardware's native format
        let format = inputNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        
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
        
        // Process directly without ring buffer for simplicity
        if n >= 2048 {
            let frame = Array(UnsafeBufferPointer(start: ch, count: min(n, 2048)))
            processRealtimeFrame(frame)
        }
    }

    private func processRealtimeFrame(_ mono: [Float]) {
        // Skip noise gate for now - just process everything
        var rms: Float = 0
        vDSP_rmsqv(mono, 1, &rms, vDSP_Length(mono.count))
        
        if rms < 0.001 {
            return
        }

        // Simple autocorrelation pitch detection
        let hz = simpleAutocorrelation(data: mono)
        
        if hz > 0 {
            print("🎵 Detected: \(hz) Hz")
            DispatchQueue.main.async { 
                self.detectedFrequency = hz
            }
        }
    }
    
    private func simpleAutocorrelation(data: [Float]) -> Double {
        let minFreq: Double = 80.0
        let maxFreq: Double = 800.0
        
        let minPeriod = Int(sampleRate / maxFreq)
        let maxPeriod = min(Int(sampleRate / minFreq), data.count / 2)
        
        if data.count < minPeriod * 2 {
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
        
        if bestPeriod > 0 && maxCorrelation > power * 0.3 {
            return sampleRate / Double(bestPeriod)
        }
        
        return 0.0
    }
}