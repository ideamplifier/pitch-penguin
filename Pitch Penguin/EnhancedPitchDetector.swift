//
//  EnhancedPitchDetector.swift
//  Pitch Penguin
//
//  Enhanced pitch detection with parabolic interpolation and octave error prevention
//

import Foundation
import Accelerate

class EnhancedPitchDetector {
    private let sampleRate: Double
    
    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }
    
    // MARK: - Parabolic Interpolation
    
    /// Refines peak position using parabolic interpolation for sub-sample accuracy
    func parabolicRefine(_ values: [Float], at peakIndex: Int) -> Double {
        guard peakIndex > 0 && peakIndex < values.count - 1 else {
            return Double(peakIndex)
        }
        
        let y1 = Double(values[peakIndex - 1])
        let y2 = Double(values[peakIndex])
        let y3 = Double(values[peakIndex + 1])
        
        let denominator = (y1 - 2*y2 + y3)
        guard abs(denominator) > 1e-12 else {
            return Double(peakIndex)
        }
        
        let delta = 0.5 * (y1 - y3) / denominator
        return Double(peakIndex) + delta
    }
    
    // MARK: - Octave Error Prevention
    
    /// Guards against octave errors by comparing candidates with target frequency
    func octaveGuard(detected: Double, target: Double?) -> Double {
        guard let target = target else { return detected }
        
        // Check octave candidates (half, same, double)
        let candidates = [detected * 0.5, detected, detected * 2.0]
        
        // Return the candidate closest to target
        return candidates.min(by: { abs($0 - target) < abs($1 - target) }) ?? detected
    }
    
    // MARK: - Enhanced Autocorrelation
    
    /// Performs autocorrelation with parabolic interpolation for improved accuracy
    func enhancedAutocorrelation(data: [Float], minFreq: Double = 70.0, maxFreq: Double = 1200.0) -> Double? {
        let minPeriod = max(2, Int(sampleRate / maxFreq))
        let maxPeriod = min(Int(sampleRate / minFreq), data.count / 2)
        
        guard maxPeriod > minPeriod else { return nil }
        
        // Calculate autocorrelation function
        var acf = [Float](repeating: 0, count: maxPeriod + 1)
        
        for lag in minPeriod...maxPeriod {
            var sum: Float = 0
            let count = data.count - lag
            
            for i in 0..<count {
                sum += data[i] * data[i + lag]
            }
            acf[lag] = sum / Float(count)
        }
        
        // Find the peak in ACF
        var maxValue: Float = 0
        var maxIndex = 0
        
        for i in (minPeriod + 1)..<maxPeriod {
            // Look for local maxima
            if acf[i] > acf[i-1] && acf[i] > acf[i+1] && acf[i] > maxValue {
                maxValue = acf[i]
                maxIndex = i
            }
        }
        
        guard maxIndex > 0 else { return nil }
        
        // Calculate signal power for threshold check
        var power: Float = 0
        vDSP_measqv(data, 1, &power, vDSP_Length(data.count))
        
        // Only accept if correlation is strong enough (lowered threshold)
        guard maxValue > power * 0.2 else { return nil }
        
        // Apply parabolic interpolation for sub-sample accuracy
        let refinedPeriod = parabolicRefine(acf, at: maxIndex)
        let frequency = sampleRate / refinedPeriod
        
        // Validate frequency range
        guard frequency >= minFreq && frequency <= maxFreq else { return nil }
        
        return frequency
    }
    
    // MARK: - YIN Algorithm with Refinement
    
    /// Enhanced YIN algorithm with parabolic interpolation
    func enhancedYIN(data: [Float], threshold: Float = 0.15) -> Double? {  // Slightly higher threshold for stability
        let minFreq = 70.0
        let maxFreq = 1200.0
        
        let minPeriod = Int(sampleRate / maxFreq)
        let maxPeriod = min(Int(sampleRate / minFreq), data.count / 2)
        
        guard data.count >= minPeriod * 2 else { return nil }
        
        // Calculate difference function
        var yinBuffer = [Float](repeating: 0, count: maxPeriod)
        
        for tau in 1..<maxPeriod {
            var sum: Float = 0
            let limit = min(data.count - tau, data.count / 2)
            
            for i in 0..<limit {
                let diff = data[i] - data[i + tau]
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
        var bestTau = minPeriod
        
        for tau in minPeriod..<(maxPeriod - 1) {
            if yinBuffer[tau] < threshold {
                // Find the true minimum
                while tau + 1 < maxPeriod && yinBuffer[tau + 1] < yinBuffer[tau] {
                    bestTau = tau + 1
                }
                bestTau = tau
                break
            }
        }
        
        // If no good minimum found, return nil
        guard bestTau < maxPeriod - 1 && yinBuffer[bestTau] < threshold else {
            return nil
        }
        
        // Apply parabolic interpolation
        let refinedTau = parabolicRefine(yinBuffer, at: bestTau)
        let frequency = sampleRate / refinedTau
        
        // Validate frequency range
        guard frequency >= minFreq && frequency <= maxFreq else { return nil }
        
        return frequency
    }
    
    // MARK: - Hybrid Detection
    
    /// Combines multiple algorithms for robust pitch detection
    func detectPitch(data: [Float], targetFrequency: Double? = nil) -> Double? {
        // Try YIN first (generally more accurate)
        if let yinFreq = enhancedYIN(data: data) {
            // Apply octave guard if target is known
            return octaveGuard(detected: yinFreq, target: targetFrequency)
        }
        
        // Fallback to autocorrelation
        if let acfFreq = enhancedAutocorrelation(data: data) {
            return octaveGuard(detected: acfFreq, target: targetFrequency)
        }
        
        return nil
    }
}