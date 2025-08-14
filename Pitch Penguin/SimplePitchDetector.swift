//
//  SimplePitchDetector.swift
//  Pitch Penguin
//
//  Simple pitch detection without external dependencies
//

import AVFoundation
import Accelerate
import SwiftUI

class SimplePitchDetector: ObservableObject {
    @Published var frequency: Float = 0
    @Published var amplitude: Float = 0
    @Published var isRecording = false
    
    private var audioEngine: AVAudioEngine!
    private var inputNode: AVAudioInputNode!
    private var sampleRate: Double = 44100.0  // Default, will be updated from actual format
    private var enhancedDetector: EnhancedPitchDetector?
    private var noiseGate: AdaptiveNoiseGate?
    
    // Stabilization
    private var frequencyBuffer: [Float] = []
    private let bufferSize = 5
    
    init() {
        setupAudio()
        
        #if DEBUG
        // GPT의 UI 테스트 - 바늘이 실제로 움직이는지 확인
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            print("🧪 Starting UI test - needle should move!")
            var testAngle = 0.0
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                testAngle += 30
                if testAngle > 300 { testAngle = 80 }
                
                // Simulate frequency change to test needle
                let testFreq = Float(testAngle)
                self.frequency = testFreq
                self.amplitude = 0.1
                print("🧪 Test: Setting frequency to \(testFreq) Hz")
                
                // Stop test after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    timer.invalidate()
                    print("🧪 UI test completed")
                }
            }
        }
        #endif
    }
    
    private func setupAudio() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])
            try session.setActive(true)
            
            let format = inputNode.outputFormat(forBus: 0)
            sampleRate = format.sampleRate
            
            print("🎛 Initial format - SR: \(sampleRate), Channels: \(format.channelCount)")
            
            // Initialize enhanced detector with actual sample rate
            enhancedDetector = EnhancedPitchDetector(sampleRate: sampleRate)
            
            // Initialize adaptive noise gate with shorter warmup
            noiseGate = AdaptiveNoiseGate(warmupDuration: 5)  // Reduced for faster response
            
            // Install tap with nil format to let system choose
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
                guard let self = self else { return }
                
                // Update sample rate if different
                let actualSR = buffer.format.sampleRate
                if self.sampleRate != actualSR {
                    print("🔄 Sample rate mismatch! Updating from \(self.sampleRate) to \(actualSR)")
                    self.sampleRate = actualSR
                    self.enhancedDetector = EnhancedPitchDetector(sampleRate: actualSR)
                }
                
                self.processBuffer(buffer)
            }
            
            try audioEngine.start()
            isRecording = true
            
            print("✅ Audio engine started with sample rate: \(sampleRate)")
        } catch {
            print("❌ Failed to start audio: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        
        isRecording = false
        frequency = 0
        amplitude = 0
        frequencyBuffer.removeAll()
        noiseGate?.reset()
    }
    
    private var tapCallCount = 0
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        // Debug: 탭 콜백 확인
        tapCallCount += 1
        if tapCallCount % 30 == 0 {
            print("🎤 TAP OK: \(tapCallCount) calls, SR=\(buffer.format.sampleRate), CH=\(buffer.format.channelCount)")
        }
        
        guard let channelData = buffer.floatChannelData?[0] else { 
            print("❌ No channel data!")
            return 
        }
        let frameCount = Int(buffer.frameLength)
        
        // Calculate RMS for amplitude
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
        
        // Check max value to see if we have signal
        var maxValue: Float = 0
        vDSP_maxmgv(channelData, 1, &maxValue, vDSP_Length(frameCount))
        
        if tapCallCount % 30 == 0 {
            print("📊 Signal check - RMS: \(rms), MAX: \(maxValue)")
        }
        
        // Check if signal is too weak (likely ambient noise)
        if rms < 0.0005 {  // Lower threshold since we're seeing 0.0006-0.0009
            // Signal too weak, likely just noise
            DispatchQueue.main.async {
                self.frequency *= 0.95
                if self.frequency < 20 {
                    self.frequency = 0
                }
                self.amplitude = 0
            }
            return
        }
        
        // Log RMS for debugging
        if rms > 0.01 {
            print("📊 RMS: \(rms)")
        }
        
        // Simple direct update for immediate response
        let detectedFreq = autocorrelation(channelData: channelData, frameCount: frameCount)
        
        if detectedFreq > 0 {
            // Add to buffer for stabilization
            frequencyBuffer.append(detectedFreq)
            if frequencyBuffer.count > bufferSize {
                frequencyBuffer.removeFirst()
            }
            
            // Use median for stability but update more frequently
            if frequencyBuffer.count >= 2 {  // Reduced from 3
                let sorted = frequencyBuffer.sorted()
                let median = sorted[sorted.count / 2]
                
                // Update UI on main thread - GPT의 핵심 지적사항
                DispatchQueue.main.async {
                    // Ensure we're on main thread for UI updates
                    precondition(Thread.isMainThread, "UI update not on main thread!")
                    
                    self.frequency = median
                    self.amplitude = rms
                    
                    // Debug log to verify UI update
                    if self.tapCallCount % 10 == 0 {
                        print("✅ UI Updated: freq=\(median) Hz, amp=\(rms)")
                    }
                }
            }
        } else {
            // Gradual decay when no signal
            DispatchQueue.main.async {
                self.frequency *= 0.95
                if self.frequency < 20 {
                    self.frequency = 0
                }
                self.amplitude *= 0.95
            }
        }
        
        return  // Skip the rest for now
        
        // Code below is temporarily disabled for testing
        /*
        if detectedFreq > 0 {
            // Add to buffer for stabilization
            frequencyBuffer.append(detectedFreq)
            if frequencyBuffer.count > bufferSize {
                frequencyBuffer.removeFirst()
            }
            
            // Use median for stability
            if frequencyBuffer.count >= 3 {
                let sorted = frequencyBuffer.sorted()
                let median = sorted[sorted.count / 2]
                
                DispatchQueue.main.async {
                    self.frequency = median
                    self.amplitude = rms
                }
            }
        }
        */
    }
    
    private func autocorrelation(channelData: UnsafeMutablePointer<Float>, frameCount: Int) -> Float {
        let minFreq: Float = 80.0
        let maxFreq: Float = 800.0
        
        let minPeriod = Int(sampleRate / Double(maxFreq))
        let maxPeriod = min(Int(sampleRate / Double(minFreq)), frameCount / 2)
        
        guard minPeriod < maxPeriod else { return 0 }
        
        var maxCorrelation: Float = 0
        var bestPeriod = 0
        
        // Find the period with maximum correlation
        for period in minPeriod..<maxPeriod {
            var correlation: Float = 0
            let count = frameCount - period
            
            // Calculate correlation for this period
            for i in 0..<count {
                correlation += channelData[i] * channelData[i + period]
            }
            
            correlation = correlation / Float(count)
            
            if correlation > maxCorrelation {
                maxCorrelation = correlation
                bestPeriod = period
            }
        }
        
        // Calculate signal power
        var power: Float = 0
        vDSP_measqv(channelData, 1, &power, vDSP_Length(frameCount))
        
        // Only return frequency if correlation is strong enough
        if bestPeriod > 0 && maxCorrelation > power * 0.3 {  // Balanced threshold
            let frequency = Float(sampleRate) / Float(bestPeriod)
            
            // Validate frequency range
            if frequency >= minFreq && frequency <= maxFreq {
                // Only log significant detections
                if maxCorrelation > power * 0.7 {
                    print("🔍 Strong signal: \(frequency) Hz (corr: \(maxCorrelation/power))")
                }
                return frequency
            } else {
                // Frequency out of range
            }
        } else if bestPeriod > 0 {
            // Correlation too weak
        }
        
        return 0
    }
}