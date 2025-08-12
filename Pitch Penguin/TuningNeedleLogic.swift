import Foundation

// Drop-in helper: map cents to a smooth, bounded angle for your existing UI.
public struct TuningNeedleMapper {
    public init() {}

    // Returns degrees in [-maxAngle, +maxAngle] with soft compression near the ends.
    public func rotationDegrees(currentHz: Double, targetHz: Double, previousDegrees: Double, maxAngle: Double = 45.0) -> Double {
        guard currentHz > 0, targetHz > 0 else {
            // graceful decay to center
            return previousDegrees * 0.96
        }
        let cents = 1200.0 * log2(currentHz / targetHz)

        // Clamp to display range ±50c, then soft-compress (tanh) so ends still show micro-movement
        let displayRange = 50.0
        let clamped = max(-displayRange, min(displayRange, cents))
        let soft = tanh(clamped / 35.0) // tweak 30~40 for feel

        let target = soft * maxAngle

        // EMA for smoothness
        let smoothed = 0.85 * previousDegrees + 0.15 * target
        return smoothed
    }
}