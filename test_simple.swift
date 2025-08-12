#!/usr/bin/env swift

import Foundation

// Test cents calculation
let targetHz = 82.41 // Low E string
let testCases: [(Double, String)] = [
    (82.0, "slightly flat"),
    (82.41, "perfect"),
    (83.0, "slightly sharp"),
    (85.0, "sharp"),
    (80.0, "flat")
]

print("Testing cents calculation:")
for (hz, description) in testCases {
    let cents = 1200.0 * log2(hz / targetHz)
    print("\(hz) Hz (\(description)): \(cents) cents")
}

// Test range clamping
print("\nTesting range clamping:")
let displayRange = 50.0
for cents in [-100.0, -50.0, 0.0, 50.0, 100.0] {
    let clamped = max(-displayRange, min(displayRange, cents))
    let soft = tanh(clamped / 35.0)
    let angle = soft * 45.0
    print("Cents: \(cents) -> Clamped: \(clamped) -> Angle: \(angle)")
}

print("\nThe needle should move smoothly within ±45 degrees!")