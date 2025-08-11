//
//  PitchDetectionAlgorithms.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import Foundation
import Accelerate

// MPM (McLeod Pitch Method) Algorithm
class MPMAlgorithm {
    private let sampleRate: Double
    private let cutoffK: Float = 0.93
    
    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }
    
    func detectPitch(data: [Float]) -> Double {
        let frameCount = data.count
        let halfSize = frameCount / 2
        
        // Calculate normalized square difference function
        var nsdf = [Float](repeating: 0, count: halfSize)
        
        // Step 1: Calculate autocorrelation
        for tau in 0..<halfSize {
            var acf: Float = 0
            var normLeft: Float = 0
            var normRight: Float = 0
            
            for i in 0..<(frameCount - tau) {
                acf += data[i] * data[i + tau]
                normLeft += data[i] * data[i]
                normRight += data[i + tau] * data[i + tau]
            }
            
            let norm = sqrt(normLeft * normRight)
            nsdf[tau] = 2 * acf / norm
        }
        
        // Step 2: Find key maxima
        var keyMaxima: [(index: Int, value: Float)] = []
        
        for i in 1..<(halfSize - 1) {
            if nsdf[i] > nsdf[i-1] && nsdf[i] > nsdf[i+1] && nsdf[i] > 0 {
                keyMaxima.append((index: i, value: nsdf[i]))
            }
        }
        
        // Step 3: Select highest key maximum above threshold
        keyMaxima.sort { $0.value > $1.value }
        
        for maxima in keyMaxima {
            if maxima.value > cutoffK {
                // Parabolic interpolation
                let tau = parabolicInterpolation(
                    values: nsdf,
                    peakIndex: maxima.index
                )
                return sampleRate / Double(tau)
            }
        }
        
        return 0.0
    }
    
    private func parabolicInterpolation(values: [Float], peakIndex: Int) -> Float {
        guard peakIndex > 0 && peakIndex < values.count - 1 else {
            return Float(peakIndex)
        }
        
        let y1 = values[peakIndex - 1]
        let y2 = values[peakIndex]
        let y3 = values[peakIndex + 1]
        
        let a = (y1 - 2 * y2 + y3) / 2
        let b = (y3 - y1) / 2
        
        if a == 0 {
            return Float(peakIndex)
        }
        
        let xOffset = -b / (2 * a)
        return Float(peakIndex) + xOffset
    }
}

// Harmonic Product Spectrum
class HarmonicProductSpectrum {
    func process(spectrum: [Float], harmonics: Int = 5) -> [Float] {
        var hps = spectrum
        let count = spectrum.count
        
        for harmonic in 2...harmonics {
            for i in 0..<(count / harmonic) {
                let harmonicIndex = i * harmonic
                if harmonicIndex < count {
                    hps[i] *= spectrum[harmonicIndex]
                }
            }
        }
        
        return hps
    }
    
    func findFundamental(spectrum: [Float], sampleRate: Double, fftSize: Int) -> Double {
        let hps = process(spectrum: spectrum)
        
        // Find peak in HPS
        var maxValue: Float = 0
        var maxIndex = 0
        
        // Skip DC component and search within reasonable frequency range
        let minBin = Int(70.0 * Double(fftSize) / sampleRate)  // 70 Hz
        let maxBin = Int(500.0 * Double(fftSize) / sampleRate) // 500 Hz
        
        for i in minBin..<min(maxBin, hps.count) {
            if hps[i] > maxValue {
                maxValue = hps[i]
                maxIndex = i
            }
        }
        
        // Convert bin to frequency
        return Double(maxIndex) * sampleRate / Double(fftSize)
    }
}

// Zero Crossing Rate Analysis
class ZeroCrossingAnalysis {
    func calculateZCR(data: [Float]) -> Float {
        var crossings = 0
        
        for i in 1..<data.count {
            if (data[i] >= 0) != (data[i-1] >= 0) {
                crossings += 1
            }
        }
        
        return Float(crossings) / Float(data.count - 1)
    }
    
    func estimateFrequency(data: [Float], sampleRate: Double) -> Double {
        let zcr = calculateZCR(data: data)
        // Approximate frequency from zero crossing rate
        return Double(zcr) * sampleRate / 2.0
    }
}

// Comb Filter for harmonic enhancement
class CombFilter {
    func apply(data: [Float], fundamentalPeriod: Int, gain: Float = 0.7) -> [Float] {
        var filtered = data
        
        for i in fundamentalPeriod..<data.count {
            filtered[i] += gain * data[i - fundamentalPeriod]
        }
        
        return filtered
    }
}

// Bitstream Autocorrelation - Ultra-fast pitch detection
class BitstreamPitchDetector {
    private let sampleRate: Double
    private let minFreq: Double = 65.0  // C2
    private let maxFreq: Double = 500.0 // B4 + margin
    
    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }
    
    func detectPitch(data: [Float]) -> Double {
        let frameCount = data.count
        let maxPeriod = min(Int(sampleRate / minFreq), frameCount / 2)
        let minPeriod = Int(sampleRate / maxFreq)
        
        // Step 1: Convert signal to 1-bit stream (zero crossing)
        var bitstream = [UInt64](repeating: 0, count: (frameCount + 63) / 64)
        
        // Batch process 64 samples at a time for efficiency
        for i in 0..<frameCount {
            if data[i] >= 0 {
                let wordIndex = i / 64
                let bitIndex = i % 64
                bitstream[wordIndex] |= (1 << bitIndex)
            }
        }
        
        // Step 2: Calculate correlations using XOR
        var correlations = [Float](repeating: Float.infinity, count: maxPeriod)
        
        for tau in minPeriod..<maxPeriod {
            var mismatchCount: Int = 0
            let words = (frameCount - tau) / 64
            
            // Process 64 bits at a time
            for w in 0..<words {
                let i = w * 64
                let j = i + tau
                let word1 = getBits(bitstream: bitstream, start: i, count: 64)
                let word2 = getBits(bitstream: bitstream, start: j, count: 64)
                let xorResult = word1 ^ word2
                mismatchCount += xorResult.nonzeroBitCount
            }
            
            // Handle remaining bits
            let remainingBits = (frameCount - tau) % 64
            if remainingBits > 0 {
                let i = words * 64
                let j = i + tau
                let word1 = getBits(bitstream: bitstream, start: i, count: remainingBits)
                let word2 = getBits(bitstream: bitstream, start: j, count: remainingBits)
                let xorResult = word1 ^ word2
                mismatchCount += xorResult.nonzeroBitCount
            }
            
            correlations[tau] = Float(mismatchCount) / Float(frameCount - tau)
        }
        
        // Step 3: Find minimum correlation (best match)
        var minValue: Float = Float.infinity
        var minTau = minPeriod
        
        for tau in minPeriod..<maxPeriod {
            if correlations[tau] < minValue {
                minValue = correlations[tau]
                minTau = tau
            }
        }
        
        // Threshold check
        if minValue > 0.25 {
            return 0.0
        }
        
        // Step 4: Parabolic interpolation
        var betterTau = Float(minTau)
        if minTau > minPeriod && minTau < maxPeriod - 1 {
            let s0 = correlations[minTau - 1]
            let s1 = correlations[minTau]
            let s2 = correlations[minTau + 1]
            
            let a = (s0 - 2 * s1 + s2) / 2
            let b = (s2 - s0) / 2
            
            if a != 0 && a < 0 { // Ensure we have a minimum
                betterTau -= b / (2 * a)
            }
        }
        
        return sampleRate / Double(betterTau)
    }
    
    private func getBits(bitstream: [UInt64], start: Int, count: Int) -> UInt64 {
        let wordIndex = start / 64
        let bitOffset = start % 64
        
        if bitOffset == 0 && count == 64 {
            return bitstream[wordIndex]
        }
        
        var result: UInt64 = 0
        for i in 0..<count {
            let bitPos = start + i
            let word = bitPos / 64
            let bit = bitPos % 64
            if word < bitstream.count && (bitstream[word] & (1 << bit)) != 0 {
                result |= (1 << i)
            }
        }
        return result
    }
}

// Hybrid Pitch Detector
class HybridPitchDetector {
    private let yinThreshold: Float = 0.15
    private let sampleRate: Double
    private let mpmDetector: MPMAlgorithm
    private let hps: HarmonicProductSpectrum
    private let zcAnalysis: ZeroCrossingAnalysis
    private let bitstreamDetector: BitstreamPitchDetector
    
    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.mpmDetector = MPMAlgorithm(sampleRate: sampleRate)
        self.hps = HarmonicProductSpectrum()
        self.zcAnalysis = ZeroCrossingAnalysis()
        self.bitstreamDetector = BitstreamPitchDetector(sampleRate: sampleRate)
    }
    
    func detectPitch(data: [Float], yinResult: Double) -> Double {
        // Bitstream detection (fastest)
        let bitstreamResult = bitstreamDetector.detectPitch(data: data)
        
        // If bitstream gives strong result, trust it for speed
        if bitstreamResult > 0 {
            // Quick validation with YIN
            if yinResult > 0 {
                let difference = abs(yinResult - bitstreamResult) / yinResult
                if difference < 0.05 { // Within 5% - very confident
                    return bitstreamResult
                }
            } else {
                // No YIN result, but bitstream found something
                return bitstreamResult
            }
        }
        
        // MPM detection for higher accuracy when needed
        let mpmResult = mpmDetector.detectPitch(data: data)
        
        // Zero crossing validation
        let zcEstimate = zcAnalysis.estimateFrequency(data: data, sampleRate: sampleRate)
        
        // Cross-validate results
        var candidates: [(freq: Double, confidence: Double)] = []
        
        if bitstreamResult > 0 {
            candidates.append((freq: bitstreamResult, confidence: 1.2)) // Prefer for speed
        }
        
        if yinResult > 0 {
            candidates.append((freq: yinResult, confidence: 1.0))
        }
        
        if mpmResult > 0 {
            candidates.append((freq: mpmResult, confidence: 0.9))
        }
        
        // Validate all candidates
        for i in 0..<candidates.count {
            // Check consistency between algorithms
            var consistencyScore = 1.0
            for j in 0..<candidates.count where i != j {
                let diff = abs(candidates[i].freq - candidates[j].freq) / candidates[i].freq
                if diff < 0.05 {
                    consistencyScore += 0.5
                }
            }
            candidates[i].confidence *= consistencyScore
            
            // Validate with zero crossing
            let zcDiff = abs(candidates[i].freq - zcEstimate) / candidates[i].freq
            if zcDiff < 0.3 {
                candidates[i].confidence *= (1.0 + (0.3 - zcDiff))
            } else if zcDiff > 0.5 {
                candidates[i].confidence *= 0.5
            }
        }
        
        // Return highest confidence result
        let best = candidates.max { $0.confidence < $1.confidence }
        return best?.freq ?? 0.0
    }
}