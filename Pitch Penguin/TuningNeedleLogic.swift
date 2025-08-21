import Foundation

// MARK: - Slew Limiter

final class SlewLimiter {
    private var last = 0.0
    private let maxDegPerSec = 240.0
    func step(to target: Double, dt: Double = 0.05) -> Double {
        let m = maxDegPerSec * dt
        let d = max(-m, min(m, target - last))
        last += d
        if abs(last - target) < 1.5 { last = target }
        return last
    }
}

// MARK: - Needle mapping

final class TuningNeedleLogic {
    private let maxAngle = 46.0
    private let slewLimiter = SlewLimiter()
    func angleDegrees(for cents: Double, locked: Bool, previousDegrees: Double) -> Double {
        let displayRange = 50.0
        let clamped = max(-displayRange, min(displayRange, cents))
        let tapered = locked ? tanh(clamped / 30.0) : tanh(clamped / 35.0)
        let target = tapered * maxAngle
        let limited = slewLimiter.step(to: target, dt: 0.05)
        let smoothed = 0.85 * previousDegrees + 0.15 * limited
        return smoothed
    }
}
