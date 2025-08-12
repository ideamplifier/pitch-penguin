import AVFoundation
import Accelerate

// 검증된 간단한 튜너 구현
class SimpleTuner: NSObject, ObservableObject {
    @Published var frequency: Double = 0
    @Published var note: String = "--"
    @Published var cents: Double = 0
    
    private var audioEngine: AVAudioEngine!
    private var mic: AVAudioInputNode!
    private var sampleRate = 48000.0  // Will be set from actual format
    private let bufferSize = 4096
    
    // 표준 A4 = 440Hz 기준 노트 주파수
    let noteFrequencies: [(note: String, frequency: Double)] = [
        ("C", 65.41), ("C#", 69.30), ("D", 73.42), ("D#", 77.78),
        ("E", 82.41), ("F", 87.31), ("F#", 92.50), ("G", 98.00),
        ("G#", 103.83), ("A", 110.00), ("A#", 116.54), ("B", 123.47)
    ]
    
    override init() {
        super.init()
        setupAudio()
    }
    
    func setupAudio() {
        audioEngine = AVAudioEngine()
        mic = audioEngine.inputNode
        
        // Use the hardware's native format to avoid mismatch
        let format = mic.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        
        // Install tap with the native format
        mic.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferSize), format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }
    }
    
    func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            
            try audioEngine.start()
        } catch {
            print("Error starting: \(error)")
        }
    }
    
    func stop() {
        audioEngine.stop()
        mic.removeTap(onBus: 0)
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Convert to mono if needed
        var monoData: [Float]
        if channelCount > 1 {
            monoData = [Float](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channelData[channel][i]
                }
                monoData[i] = sum / Float(channelCount)
            }
        } else {
            monoData = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }
        
        // 간단한 자기상관 피치 검출
        let pitch = detectPitchAutocorrelation(data: &monoData[0], count: frameCount)
        
        DispatchQueue.main.async {
            self.frequency = pitch
            self.updateNoteAndCents(frequency: pitch)
        }
    }
    
    private func detectPitchAutocorrelation(data: UnsafeMutablePointer<Float>, count: Int) -> Double {
        // 노이즈 체크
        var rms: Float = 0
        vDSP_rmsqv(data, 1, &rms, vDSP_Length(count))
        if rms < 0.01 { return 0 } // 노이즈 게이트
        
        // 자기상관 계산
        let minPeriod = Int(sampleRate / 600.0) // 600Hz max
        let maxPeriod = Int(sampleRate / 80.0)  // 80Hz min
        
        var maxCorr: Float = 0
        var bestPeriod = 0
        
        for period in minPeriod..<min(maxPeriod, count/2) {
            var corr: Float = 0
            vDSP_dotpr(data, 1, data.advanced(by: period), 1, &corr, vDSP_Length(count - period))
            
            if corr > maxCorr {
                maxCorr = corr
                bestPeriod = period
            }
        }
        
        // 신뢰도 체크
        if maxCorr < rms * rms * Float(count - bestPeriod) * 0.3 {
            return 0
        }
        
        return bestPeriod > 0 ? sampleRate / Double(bestPeriod) : 0
    }
    
    private func updateNoteAndCents(frequency: Double) {
        guard frequency > 0 else {
            note = "--"
            cents = 0
            return
        }
        
        // 가장 가까운 노트 찾기
        let noteNum = 12 * log2(frequency / 440.0) + 69
        let nearestNote = Int(round(noteNum))
        let noteIndex = ((nearestNote - 12) % 12 + 12) % 12
        
        note = noteFrequencies[noteIndex].note
        
        // Cents 계산
        let targetFreq = 440.0 * pow(2.0, Double(nearestNote - 69) / 12.0)
        cents = 1200 * log2(frequency / targetFreq)
    }
}