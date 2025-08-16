//
//  TuningNeedleMapper.swift
//  Pitch Penguin
//
//  Maps frequency differences to needle rotation angles
//

import Foundation

struct TuningNeedleMapper {
    func rotationDegrees(currentHz: Double, targetHz: Double, previousDegrees: Double, maxAngle: Double = 45.0) -> Double {
        guard currentHz > 0, targetHz > 0 else {
            return previousDegrees * 0.96
        }
        let cents = 1200.0 * log2(currentHz / targetHz)
        
        let displayRange = 50.0
        let clamped = max(-displayRange, min(displayRange, cents))
        let soft = tanh(clamped / 35.0)
        
        let target = soft * maxAngle
        let smoothed = 0.85 * previousDegrees + 0.15 * target
        return smoothed
    }
}