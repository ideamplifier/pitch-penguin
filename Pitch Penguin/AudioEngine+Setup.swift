import AVFoundation

extension AudioEngine {
    func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.03) // ~30ms
        try session.setActive(true, options: [])
        print("Session configured: sr=\(session.sampleRate), io=\(session.ioBufferDuration)")
    }

    func startEngineWithTunedTap() throws {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        
        // Get the hardware's actual format first
        let inputFormat = inputNode.outputFormat(forBus: bus)
        
        // Prepare and start the engine with the hardware format
        audioEngine.prepare()
        try audioEngine.start()

        // tap은 1024로 고정 (낮은 지연), 내부에서 2048/75% overlap 처리
        let tapSize: AVAudioFrameCount = 1024
        inputNode.installTap(onBus: bus, bufferSize: tapSize, format: inputFormat) { [weak self] buffer, time in
            self?.ingest(buffer: buffer) // 아래에 정의할 ring-buffer 루틴
        }
    }
}