//
//  AdaptiveBandPassFilter.swift
//  Pitch Penguin
//
//  Adaptive band-pass filter that adjusts to actual sample rate
//

import Accelerate
import Foundation

class AdaptiveBandPassFilter {
    private var sampleRate: Double
    
    // Butterworth 2nd order IIR filter coefficients
    private var hpfB: [Float] = []
    private var hpfA: [Float] = []
    private var lpfB: [Float] = []
    private var lpfA: [Float] = []
    
    // Filter states (for continuity between frames)
    private var hpfZ1: Float = 0
    private var hpfZ2: Float = 0
    private var lpfZ1: Float = 0
    private var lpfZ2: Float = 0
    
    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        updateCoefficients()
    }
    
    func updateSampleRate(_ newRate: Double) {
        sampleRate = newRate
        updateCoefficients()
        // Reset states to avoid instability
        hpfZ1 = 0
        hpfZ2 = 0
        lpfZ1 = 0
        lpfZ2 = 0
    }
    
    private func updateCoefficients() {
        // High-pass filter at 60 Hz (removes DC and very low frequencies)
        let hpfFreq = 60.0
        let hpfOmega = 2.0 * .pi * hpfFreq / sampleRate
        let hpfAlpha = sin(hpfOmega) / sqrt(2.0)
        let hpfCos = cos(hpfOmega)
        
        let hpfA0 = 1.0 + hpfAlpha
        hpfB = [
            Float((1.0 + hpfCos) / 2.0 / hpfA0),
            Float(-(1.0 + hpfCos) / hpfA0),
            Float((1.0 + hpfCos) / 2.0 / hpfA0)
        ]
        hpfA = [
            1.0,
            Float(-2.0 * hpfCos / hpfA0),
            Float((1.0 - hpfAlpha) / hpfA0)
        ]
        
        // Low-pass filter at 3000 Hz (removes high frequency noise)
        let lpfFreq = 3000.0
        let lpfOmega = 2.0 * .pi * lpfFreq / sampleRate
        let lpfAlpha = sin(lpfOmega) / sqrt(2.0)
        let lpfCos = cos(lpfOmega)
        
        let lpfA0 = 1.0 + lpfAlpha
        lpfB = [
            Float((1.0 - lpfCos) / 2.0 / lpfA0),
            Float((1.0 - lpfCos) / lpfA0),
            Float((1.0 - lpfCos) / 2.0 / lpfA0)
        ]
        lpfA = [
            1.0,
            Float(-2.0 * lpfCos / lpfA0),
            Float((1.0 - lpfAlpha) / lpfA0)
        ]
    }
    
    func apply(_ input: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: input.count)
        
        // Apply HPF then LPF
        for i in 0..<input.count {
            // High-pass filter (Direct Form II)
            let hpfW = input[i] - hpfA[1] * hpfZ1 - hpfA[2] * hpfZ2
            let hpfY = hpfB[0] * hpfW + hpfB[1] * hpfZ1 + hpfB[2] * hpfZ2
            hpfZ2 = hpfZ1
            hpfZ1 = hpfW
            
            // Low-pass filter (Direct Form II)
            let lpfW = hpfY - lpfA[1] * lpfZ1 - lpfA[2] * lpfZ2
            output[i] = lpfB[0] * lpfW + lpfB[1] * lpfZ1 + lpfB[2] * lpfZ2
            lpfZ2 = lpfZ1
            lpfZ1 = lpfW
            
            // Prevent NaN/Inf propagation
            if output[i].isNaN || output[i].isInfinite {
                output[i] = 0
                // Reset filter states
                hpfZ1 = 0
                hpfZ2 = 0
                lpfZ1 = 0
                lpfZ2 = 0
            }
        }
        
        return output
    }
    
    func reset() {
        hpfZ1 = 0
        hpfZ2 = 0
        lpfZ1 = 0
        lpfZ2 = 0
    }
}