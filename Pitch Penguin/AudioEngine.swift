
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
    
    private let bufferSize: UInt32 = 4096
    private let sampleRate: Double = 44100.0
    
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
            
            let recordingFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
            
            inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, _ in
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
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        
        let frequency = detectPitch(channelData: channelData, frameCount: frameCount)
        
        DispatchQueue.main.async {
            self.detectedFrequency = frequency
        }
    }
    
    private func detectPitch(channelData: UnsafePointer<Float>, frameCount: Int) -> Double {
        let threshold: Float = 0.1
        let minFreq: Double = 50.0
        let maxFreq: Double = 500.0
        
        let minPeriod = Int(sampleRate / maxFreq)
        let maxPeriod = Int(sampleRate / minFreq)
        
        var yinBuffer = [Float](repeating: 0, count: maxPeriod)
        
        for tau in 1..<maxPeriod {
            var sum: Float = 0
            for j in 0..<min(maxPeriod, frameCount - tau) {
                let diff = channelData[j] - channelData[j + tau]
                sum += diff * diff
            }
            yinBuffer[tau] = sum
        }
        
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
        
        var tau = minPeriod
        while tau < maxPeriod - 1 {
            if yinBuffer[tau] < threshold {
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
        
        var betterTau: Float
        if tau > 0 && tau < maxPeriod - 1 {
            let s0 = yinBuffer[tau - 1]
            let s1 = yinBuffer[tau]
            let s2 = yinBuffer[tau + 1]
            
            let a = (s2 - s0) / 2.0
            let b = 2.0 * s1 - s0 - s2
            
            if a != 0 {
                betterTau = Float(tau) - b / (2.0 * a)
            } else {
                betterTau = Float(tau)
            }
        } else {
            betterTau = Float(tau)
        }
        
        return sampleRate / Double(betterTau)
    }
    
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
}
