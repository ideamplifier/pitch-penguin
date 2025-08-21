//
//  NoteMath.swift
//  Pitch Penguin
//
//  Note mathematics and frequency calculations
//

import Foundation

enum NoteMath {
    static func a4(_ hz: Double = 440.0) -> Double { hz }

    /// 12-TET note number (MIDI-like) rounded to nearest
    static func noteNumber(for f: Double, a4: Double = 440.0) -> Int {
        guard f > 0 else { return 0 }
        let n = 69.0 + 12.0 * log2(f / a4)
        return Int(round(n))
    }

    static func name(forNote n: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return names[(n % 12 + 12) % 12]
    }

    static func centsOffset(f: Double, toNoteNumber nn: Int, a4 _: Double = 440.0) -> Double {
        guard f > 0 else { return 0 }
        let fRef = 440.0 * pow(2.0, Double(nn - 69) / 12.0)
        return 1200.0 * log2(f / fRef)
    }

    enum GuitarStandard {
        // E2 A2 D3 G3 B3 E4
        static let stringsHz: [Double] = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]
    }

    /// Choose auto string index (0..5) for a given f0, with octave-penalty & lock bias.
    static func autoStringIndex(for f0: Double, prevLocked: Int?) -> Int {
        var bestIdx = 0
        var bestScore = Double.greatestFiniteMagnitude
        for (i, t) in GuitarStandard.stringsHz.enumerated() {
            let cents = abs(1200.0 * log2(f0 / t))
            let centsHalf = abs(1200.0 * log2(f0 / (t / 2)))
            let centsDouble = abs(1200.0 * log2(f0 / (t * 2)))
            // Penalize near-octave confusions strongly
            let octavePenalty = max(0.0, 240.0 - min(centsHalf, centsDouble))
            let lockBias = (prevLocked == i) ? -25.0 : 0.0
            let score = cents + 0.9 * octavePenalty + lockBias
            if score < bestScore { bestScore = score; bestIdx = i }
        }
        return bestIdx
    }
}

enum GuitarStandard {
    // E2 A2 D3 G3 B3 E4
    static let stringsHz: [Double] = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63]
}

enum AutoStringSelector {
    static func pickString(for f0: Double, prevLocked: Int?) -> Int {
        return NoteMath.autoStringIndex(for: f0, prevLocked: prevLocked)
    }
}
