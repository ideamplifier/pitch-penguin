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
            
            // Initialize enhanced detector with actual sample rate
            enhancedDetector = EnhancedPitchDetector(sampleRate: sampleRate)
            
            // Initialize adaptive noise gate
            noiseGate = AdaptiveNoiseGate(warmupDuration: 20)
            
            // Install tap with 4096 samples for better accuracy
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                self?.processBuffer(buffer)
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
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        
        // Calculate RMS for amplitude
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
        
        // Use adaptive noise gate
        guard let gate = noiseGate, gate.shouldPassSignal(rms: rms) else {
            // Smooth decay when no signal
            DispatchQueue.main.async {
                self.frequency *= 0.95
                if self.frequency < 20 {
                    self.frequency = 0
                }
                self.amplitude = 0
            }
            return
        }
        
        // Use enhanced pitch detection
        let floatData = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        let detectedFreq = Float(enhancedDetector?.detectPitch(data: floatData) ?? 0)
        
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
        if bestPeriod > 0 && maxCorrelation > power * 0.3 {
            let frequency = Float(sampleRate) / Float(bestPeriod)
            
            // Validate frequency range
            if frequency >= minFreq && frequency <= maxFreq {
                return frequency
            }
        }
        
        return 0
    }
}