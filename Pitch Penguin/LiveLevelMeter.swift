import Accelerate
import Combine

final class LiveLevelMeter: ObservableObject {
    @Published var level: Float = 0 // 0...1
    func update(from frame: [Float]) {
        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(frame.count))
        // Simple mapping to 0..1 (tweak if needed)
        let mapped = min(max(rms * 10, 0), 1)
        DispatchQueue.main.async { self.level = mapped }
    }
}