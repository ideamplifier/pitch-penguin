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
    
    private let bufferSize: UInt32 = 2048  // Reduced for faster response
    private let sampleRate: Double = 44100.0
    
    // Pitch stabilization
    private var frequencyBuffer: [Double] = []
    private let bufferMaxSize = 5
    
    // Noise gate
    private let noiseGateThreshold: Float = 0.01
    
    override init() {
        super.init()
        setupAudio()
    }
    
    private func setupAudio() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
    }
    
    func startRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            
            // Use input node's format instead of creating custom format
            let inputFormat = inputNode.outputFormat(forBus: bus)
            
            inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
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
        
        // Apply noise gate
        var signalPower: Float = 0
        vDSP_measqv(monoData, 1, &signalPower, vDSP_Length(frameCount))
        signalPower = sqrt(signalPower)
        
        if signalPower < noiseGateThreshold {
            DispatchQueue.main.async {
                self.detectedFrequency = 0.0
            }
            return
        }
        
        // Apply high-pass filter to remove low frequency noise
        let filteredData = applyHighPassFilter(channelData: monoData, frameCount: frameCount)
        
        // Apply window function
        let windowedData = applyWindow(data: filteredData, frameCount: frameCount)
        
        // Detect pitch with enhanced YIN
        let frequency = detectPitch(channelData: windowedData, frameCount: frameCount)
        
        // Stabilize frequency
        if frequency > 0 {
            stabilizeFrequency(frequency)
        } else {
            DispatchQueue.main.async {
                self.detectedFrequency = 0.0
                self.frequencyBuffer.removeAll()
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
        
        DispatchQueue.main.async {
            self.detectedFrequency = median
        }
    }
    
    private func detectPitch(channelData: [Float], frameCount: Int) -> Double {
        let threshold: Float = 0.15  // Slightly higher for better accuracy
        let minFreq: Double = 70.0   // E2 - 20Hz for margin
        let maxFreq: Double = 400.0  // E4 + margin
        
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
}