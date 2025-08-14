//
//  AdaptiveNoiseGate.swift
//  Pitch Penguin
//
//  Adaptive noise gate that learns background noise level
//

import Foundation
import Accelerate

class AdaptiveNoiseGate {
    private var warmupFrames = 20  // Number of frames for calibration
    private var currentFrame = 0
    
    // Noise statistics
    private var noiseMean: Double = 0
    private var noiseVariance: Double = 0
    private var sampleCount: Double = 0
    
    // Gate parameters
    private let sigmaMultiplier: Double = 2.0  // Reduced for better sensitivity
    private var threshold: Double = 0.0001  // Much lower initial threshold
    private var isCalibrated = false
    
    // Smooth transition
    private var lastGateState = false
    private var gateOpenCount = 0
    private let hysteresisFrames = 3  // Require 3 consecutive frames to change state
    
    init(warmupDuration: Int = 20) {
        self.warmupFrames = warmupDuration
    }
    
    /// Process RMS value and determine if signal should pass
    func shouldPassSignal(rms: Float) -> Bool {
        let rmsDouble = Double(rms)
        
        // During warmup, collect noise statistics
        if !isCalibrated {
            updateNoiseStatistics(rmsDouble)
            
            if currentFrame >= warmupFrames {
                calculateThreshold()
                isCalibrated = true
                print("🎛 Noise gate calibrated: threshold = \(threshold)")
            }
            
            currentFrame += 1
            return false  // Don't pass signal during calibration
        }
        
        // After calibration, use adaptive threshold
        let shouldOpen = rmsDouble > threshold
        
        // Apply hysteresis to prevent rapid switching
        if shouldOpen != lastGateState {
            gateOpenCount += 1
            if gateOpenCount >= hysteresisFrames {
                lastGateState = shouldOpen
                gateOpenCount = 0
            }
        } else {
            gateOpenCount = 0
        }
        
        return lastGateState
    }
    
    private func updateNoiseStatistics(_ rms: Double) {
        // Online calculation of mean and variance (Welford's algorithm)
        sampleCount += 1
        let delta = rms - noiseMean
        noiseMean += delta / sampleCount
        let delta2 = rms - noiseMean
        noiseVariance += delta * delta2
    }
    
    private func calculateThreshold() {
        // Calculate standard deviation
        let variance = noiseVariance / max(sampleCount - 1, 1)
        let standardDeviation = sqrt(max(variance, 1e-12))
        
        // Set threshold as mean + (multiplier * standard deviation)
        threshold = noiseMean + (sigmaMultiplier * standardDeviation)
        
        // Ensure minimum threshold - very low for guitar
        threshold = max(threshold, 0.00001)
    }
    
    /// Reset calibration (useful when environment changes)
    func reset() {
        currentFrame = 0
        noiseMean = 0
        noiseVariance = 0
        sampleCount = 0
        isCalibrated = false
        lastGateState = false
        gateOpenCount = 0
    }
    
    /// Get current threshold (for debugging)
    var currentThreshold: Double {
        return threshold
    }
    
    /// Check if calibration is complete
    var calibrationComplete: Bool {
        return isCalibrated
    }
}