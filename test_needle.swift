#!/usr/bin/env swift

// Test the TuningNeedleMapper logic
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

// Test cases
let mapper = TuningNeedleMapper()
var rotation: Double = 0

// Test frequencies near target (should show small movements)
print("Testing near-target frequencies:")
let targetHz = 82.41 // Low E string
let testCases = [
    (82.0, "slightly flat"),
    (82.41, "perfect"),
    (83.0, "slightly sharp"),
    (85.0, "sharp"),
    (80.0, "flat"),
]

for (hz, description) in testCases {
    rotation = mapper.rotationDegrees(currentHz: hz, targetHz: targetHz, previousDegrees: rotation)
    let cents = 1200.0 * log2(hz / targetHz)
    print(String(format: "%.1f Hz (%s): %.1f cents -> %.1f degrees", hz, description, cents, rotation))
}

// Test extreme cases (should be clamped)
print("\nTesting extreme frequencies:")
let extremeCases = [
    (150.0, "way too sharp"),
    (40.0, "way too flat"),
]

for (hz, description) in extremeCases {
    rotation = mapper.rotationDegrees(currentHz: hz, targetHz: targetHz, previousDegrees: rotation)
    let cents = 1200.0 * log2(hz / targetHz)
    print(String(format: "%.1f Hz (%s): %.1f cents -> %.1f degrees", hz, description, cents, rotation))
}

// Test smooth transitions
print("\nTesting smooth transitions (simulating gradual pitch change):")
rotation = 0
for i in 0 ... 10 {
    let hz = 82.41 + Double(i) * 0.5
    rotation = mapper.rotationDegrees(currentHz: hz, targetHz: targetHz, previousDegrees: rotation)
    print(String(format: "%.2f Hz -> %.2f degrees", hz, rotation))
}

print("\nIf degrees change smoothly and stay within ±45, the needle mapper is working correctly!")
