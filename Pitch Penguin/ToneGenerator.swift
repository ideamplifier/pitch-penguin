//
//  ToneGenerator.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import AVFoundation

class ToneGenerator {
    private var audioEngine = AVAudioEngine()
    private var toneNode: AVAudioSourceNode?
    private var isPlaying = false
    
    func playTone(frequency: Double, duration: Double = 1.0) {
        stopTone()
        
        let sampleRate = 44100.0
        let amplitude: Float = 0.25
        
        toneNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let phaseIncrement = 2.0 * Double.pi * frequency / sampleRate
            
            for frame in 0..<Int(frameCount) {
                let sample = Float(sin(self.phase))
                self.phase += phaseIncrement
                
                // Keep phase in reasonable range
                if self.phase > 2.0 * Double.pi {
                    self.phase -= 2.0 * Double.pi
                }
                
                for buffer in ablPointer {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    buf[frame] = sample * amplitude
                }
            }
            
            return noErr
        }
        
        audioEngine.attach(toneNode!)
        audioEngine.connect(toneNode!, to: audioEngine.mainMixerNode, format: nil)
        
        do {
            try audioEngine.start()
            isPlaying = true
            
            // Auto stop after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.stopTone()
            }
        } catch {
            print("Error starting audio engine: \(error)")
        }
    }
    
    func stopTone() {
        if isPlaying {
            audioEngine.stop()
            if let node = toneNode {
                audioEngine.detach(node)
            }
            toneNode = nil
            isPlaying = false
            phase = 0
        }
    }
    
    private var phase: Double = 0
}