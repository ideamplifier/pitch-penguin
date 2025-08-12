import Accelerate

struct BPFilter {
    // 2차 HPF 80Hz + 2차 LPF 2.5kHz @ 48k
    var hpfCoeffs: [Double] = []
    var lpfCoeffs: [Double] = []
    var hpfState = [Float](repeating: 0, count: 5)
    var lpfState = [Float](repeating: 0, count: 5)
    
    init() {
        setupFilters()
    }
    
    mutating func setupFilters() {
        // Butterworth coefficients for 80Hz HPF @ 48kHz
        // Pre-calculated for performance
        hpfCoeffs = [0.9946, -1.9893, 0.9946, 1.9893, -0.9893]
        
        // Butterworth coefficients for 2.5kHz LPF @ 48kHz  
        // Pre-calculated for performance
        lpfCoeffs = [0.0309, 0.0618, 0.0309, 1.4339, -0.5575]
    }
    
    mutating func apply(_ x: [Float]) -> [Float] {
        var y = [Float](repeating: 0, count: x.count)
        
        // Apply HPF
        for i in 0..<x.count {
            if i >= 2 {
                y[i] = Float(hpfCoeffs[0]) * x[i] + Float(hpfCoeffs[1]) * x[i-1] + Float(hpfCoeffs[2]) * x[i-2]
                       - Float(hpfCoeffs[3]) * y[i-1] - Float(hpfCoeffs[4]) * y[i-2]
            } else if i == 1 {
                y[i] = Float(hpfCoeffs[0]) * x[i] + Float(hpfCoeffs[1]) * x[i-1]
            } else {
                y[i] = Float(hpfCoeffs[0]) * x[i]
            }
        }
        
        // Apply LPF on HPF output
        var filtered = [Float](repeating: 0, count: x.count)
        for i in 0..<y.count {
            if i >= 2 {
                filtered[i] = Float(lpfCoeffs[0]) * y[i] + Float(lpfCoeffs[1]) * y[i-1] + Float(lpfCoeffs[2]) * y[i-2]
                            - Float(lpfCoeffs[3]) * filtered[i-1] - Float(lpfCoeffs[4]) * filtered[i-2]
            } else if i == 1 {
                filtered[i] = Float(lpfCoeffs[0]) * y[i] + Float(lpfCoeffs[1]) * y[i-1]
            } else {
                filtered[i] = Float(lpfCoeffs[0]) * y[i]
            }
        }
        
        return filtered
    }
}

final class Stabilizer {
    private var last5 = [Double]()
    private let hysteresisCents = 40.0
    
    func push(_ hz: Double) -> Double {
        guard hz > 0 else { 
            last5.removeAll()
            return 0 
        }
        last5.append(hz)
        if last5.count > 5 { 
            last5.removeFirst() 
        }
        guard !last5.isEmpty else { return 0 }
        let sorted = last5.sorted()
        return sorted[sorted.count/2]
    }
    
    func allowNoteChange(current: Double, target: Double) -> Bool {
        guard current > 0 else { return true }
        let cents = 1200.0 * log2(target / current)
        return abs(cents) > hysteresisCents
    }
}

extension MPMAlgorithm {
    func recommendedCMNDThreshold() -> Float { 
        return 0.12 
    }
}