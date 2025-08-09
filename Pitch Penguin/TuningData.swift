//
//  TuningData.swift
//  Pitch Penguin
//
//  Created by EUIHYUNG JUNG on 8/8/25.
//

import Foundation

enum InstrumentType: String, CaseIterable {
    case guitar = "Guitar"
    case bass = "Bass"
    case ukulele = "Ukulele"
}

struct Tuning {
    let name: String
    let notes: [GuitarString]
}

class TuningData {
    static let guitarTunings: [Tuning] = [
        Tuning(name: "Standard", notes: [
            GuitarString(note: "E", octave: 2, frequency: 82.41),
            GuitarString(note: "A", octave: 2, frequency: 110.00),
            GuitarString(note: "D", octave: 3, frequency: 146.83),
            GuitarString(note: "G", octave: 3, frequency: 196.00),
            GuitarString(note: "B", octave: 3, frequency: 246.94),
            GuitarString(note: "E", octave: 4, frequency: 329.63)
        ]),
        Tuning(name: "Drop D", notes: [
            GuitarString(note: "D", octave: 2, frequency: 73.42),
            GuitarString(note: "A", octave: 2, frequency: 110.00),
            GuitarString(note: "D", octave: 3, frequency: 146.83),
            GuitarString(note: "G", octave: 3, frequency: 196.00),
            GuitarString(note: "B", octave: 3, frequency: 246.94),
            GuitarString(note: "E", octave: 4, frequency: 329.63)
        ]),
        Tuning(name: "Open G", notes: [
            GuitarString(note: "D", octave: 2, frequency: 73.42),
            GuitarString(note: "G", octave: 2, frequency: 98.00),
            GuitarString(note: "D", octave: 3, frequency: 146.83),
            GuitarString(note: "G", octave: 3, frequency: 196.00),
            GuitarString(note: "B", octave: 3, frequency: 246.94),
            GuitarString(note: "D", octave: 4, frequency: 293.66)
        ]),
        Tuning(name: "DADGAD", notes: [
            GuitarString(note: "D", octave: 2, frequency: 73.42),
            GuitarString(note: "A", octave: 2, frequency: 110.00),
            GuitarString(note: "D", octave: 3, frequency: 146.83),
            GuitarString(note: "G", octave: 3, frequency: 196.00),
            GuitarString(note: "A", octave: 3, frequency: 220.00),
            GuitarString(note: "D", octave: 4, frequency: 293.66)
        ])
    ]
    
    static let bassTunings: [Tuning] = [
        Tuning(name: "Standard", notes: [
            GuitarString(note: "E", octave: 1, frequency: 41.20),
            GuitarString(note: "A", octave: 1, frequency: 55.00),
            GuitarString(note: "D", octave: 2, frequency: 73.42),
            GuitarString(note: "G", octave: 2, frequency: 98.00)
        ]),
        Tuning(name: "Drop D", notes: [
            GuitarString(note: "D", octave: 1, frequency: 36.71),
            GuitarString(note: "A", octave: 1, frequency: 55.00),
            GuitarString(note: "D", octave: 2, frequency: 73.42),
            GuitarString(note: "G", octave: 2, frequency: 98.00)
        ]),
        Tuning(name: "5-String", notes: [
            GuitarString(note: "B", octave: 0, frequency: 30.87),
            GuitarString(note: "E", octave: 1, frequency: 41.20),
            GuitarString(note: "A", octave: 1, frequency: 55.00),
            GuitarString(note: "D", octave: 2, frequency: 73.42),
            GuitarString(note: "G", octave: 2, frequency: 98.00)
        ])
    ]
    
    static let ukuleleTunings: [Tuning] = [
        Tuning(name: "Standard", notes: [
            GuitarString(note: "G", octave: 4, frequency: 392.00),
            GuitarString(note: "C", octave: 4, frequency: 261.63),
            GuitarString(note: "E", octave: 4, frequency: 329.63),
            GuitarString(note: "A", octave: 4, frequency: 440.00)
        ]),
        Tuning(name: "Low G", notes: [
            GuitarString(note: "G", octave: 3, frequency: 196.00),
            GuitarString(note: "C", octave: 4, frequency: 261.63),
            GuitarString(note: "E", octave: 4, frequency: 329.63),
            GuitarString(note: "A", octave: 4, frequency: 440.00)
        ]),
        Tuning(name: "Baritone", notes: [
            GuitarString(note: "D", octave: 3, frequency: 146.83),
            GuitarString(note: "G", octave: 3, frequency: 196.00),
            GuitarString(note: "B", octave: 3, frequency: 246.94),
            GuitarString(note: "E", octave: 4, frequency: 329.63)
        ])
    ]
    
    static func getTunings(for instrument: InstrumentType) -> [Tuning] {
        switch instrument {
        case .guitar:
            return guitarTunings
        case .bass:
            return bassTunings
        case .ukulele:
            return ukuleleTunings
        }
    }
}